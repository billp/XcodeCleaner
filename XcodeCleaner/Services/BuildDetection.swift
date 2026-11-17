import Foundation

/// One row of `ps -o pid=,ppid=,comm=`.
struct RunningProcess: Equatable, Sendable {
    let pid: Int32
    let ppid: Int32
    /// Full executable path (`comm` on macOS reports the whole path).
    let path: String

    var name: String { (path as NSString).lastPathComponent }
}

/// A build currently in flight, attributed to whoever started it.
struct ActiveBuild: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        /// A build started from the Xcode app.
        case xcode
        /// An `xcodebuild` invocation (MCP servers, fastlane, scripts, CI…).
        case xcodebuild
        /// `swift build` / `swift test` / `swift run`.
        case swiftPM
        /// Compilers running outside any known build tool (make, CMake, Bazel…).
        case other
    }

    let pid: Int32
    let kind: Kind
    /// Who started it, e.g. "Xcode", "XcodeBuildMCP", "Claude Code", "Terminal".
    let source: String
    /// What's being built, when known — e.g. "AlphaBankRetail · build".
    var detail: String?
    /// The git branch checked out where the build runs (or the folder name when
    /// it isn't a git checkout).
    var branch: String?
    /// Absolute folders the build reads or writes, from its command line
    /// (`-derivedDataPath`, `-testProductsPath`, a package's `.build`…).
    var paths: [String] = []
}

/// Pure process-tree analysis: turns a `ps` snapshot into a list of builds.
enum BuildDetection {
    /// The build engine Xcode and `xcodebuild` delegate to (Swift Build in
    /// Xcode 16+, XCBuild before that). Xcode keeps it alive while idle, so it
    /// only counts as a build while it has child processes (compilers, tools).
    static let buildServiceNames: Set<String> = ["SWBBuildService", "XCBBuildService"]
    static let swiftPMNames: Set<String> = ["swift-build", "swift-test", "swift-run"]
    static let compilerNames: Set<String> = [
        "swift-frontend", "swiftc", "swift-driver", "clang", "clang++", "ld", "ld64",
    ]
    /// `xcodebuild` modes that only query and never touch build products.
    static let xcodebuildActions: Set<String> = [
        "build", "build-for-testing", "test", "test-without-building", "archive",
        "analyze", "install", "installsrc", "clean", "docbuild",
    ]
    static let queryFlags: Set<String> = [
        "-showBuildSettings", "-list", "-version", "-showsdks", "-showdestinations",
        "-showTestPlans", "-showComponent", "-help", "-usage", "-license",
        "-checkFirstLaunchStatus", "-runFirstLaunch", "-find", "-find-executable", "-find-library",
    ]

    /// `xcodebuild` flags whose value is a path the build reads or writes.
    static let xcodebuildPathFlags: [String] = [
        "-workspace", "-project", "-derivedDataPath", "-resultBundlePath", "-testProductsPath",
        "-archivePath", "-xctestrun", "-clonedSourcePackagesDirPath", "-packageCachePath",
    ]

    /// Parses `ps -o pid=,ppid=,comm=` output. Paths may contain spaces, so
    /// only the first two columns are split off.
    static func parseProcesses(_ output: String) -> [RunningProcess] {
        output.split(separator: "\n").compactMap { line in
            let parts = line.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)
            guard parts.count == 3, let pid = Int32(parts[0]), let ppid = Int32(parts[1]) else { return nil }
            return RunningProcess(pid: pid, ppid: ppid, path: parts[2].trimmingCharacters(in: .whitespaces))
        }
    }

    /// Parses `ps -o pid=,args=` output into whitespace-split argument lists.
    static func parseArguments(_ output: String) -> [Int32: [String]] {
        var result: [Int32: [String]] = [:]
        for line in output.split(separator: "\n") {
            let tokens = line.split(separator: " ").map(String.init)
            guard let first = tokens.first, let pid = Int32(first) else { continue }
            result[pid] = Array(tokens.dropFirst())
        }
        return result
    }

    /// Resolves the branch for an `xcodebuild` given its pid and its
    /// `-workspace`/`-project` argument (which may be relative or absent).
    typealias BranchResolver = (_ pid: Int32, _ containerPath: String?) -> String?

    /// - Parameter ownPID: this app's pid. Processes it launched (scans run
    ///   `xcrun simctl`, whose shim calls `xcodebuild`) are never builds.
    /// - Parameter workingDirectories: per-pid current directory, used to
    ///   resolve relative paths on a build's command line.
    static func detect(processes: [RunningProcess], arguments: [Int32: [String]] = [:],
                       workingDirectories: [Int32: String] = [:],
                       ignoringDescendantsOf ownPID: Int32? = nil,
                       branch resolveBranch: BranchResolver = { _, _ in nil }) -> [ActiveBuild] {
        let fullTree = ProcessTree(processes)
        let processes = processes.filter { process in
            guard let ownPID else { return true }
            return process.pid != ownPID && !fullTree.ancestors(of: process).contains { $0.pid == ownPID }
        }
        let tree = ProcessTree(processes)
        var builds: [ActiveBuild] = []

        for process in processes where process.name == "xcodebuild" {
            let ancestors = tree.ancestors(of: process)
            guard !ancestors.contains(where: { $0.name == "xcodebuild" }) else { continue }
            if let args = arguments[process.pid], args.contains(where: queryFlags.contains) { continue }
            let args = arguments[process.pid] ?? []
            builds.append(ActiveBuild(pid: process.pid, kind: .xcodebuild, source: source(of: ancestors),
                                      detail: xcodebuildDetail(args),
                                      branch: resolveBranch(process.pid, xcodebuildContainer(args)),
                                      paths: xcodebuildPaths(args, workingDirectory: workingDirectories[process.pid])))
        }

        for process in processes where swiftPMNames.contains(process.name) {
            let ancestors = tree.ancestors(of: process)
            guard !ancestors.contains(where: { swiftPMNames.contains($0.name) }) else { continue }
            builds.append(ActiveBuild(pid: process.pid, kind: .swiftPM, source: source(of: ancestors),
                                      paths: swiftPMPaths(arguments[process.pid] ?? [],
                                                          workingDirectory: workingDirectories[process.pid])))
        }

        for process in processes where buildServiceNames.contains(process.name) {
            let ancestors = tree.ancestors(of: process)
            // Services under xcodebuild are already counted with their xcodebuild.
            guard !ancestors.contains(where: { $0.name == "xcodebuild" }),
                  tree.hasChildren(process) else { continue }
            builds.append(ActiveBuild(pid: process.pid, kind: .xcode, source: source(of: ancestors)))
        }

        // Fallback: compilers not owned by any of the above, one build per host app.
        let rootNames = swiftPMNames.union(buildServiceNames).union(["xcodebuild"])
        var seenHosts: Set<Int32> = []
        for process in processes where compilerNames.contains(process.name) {
            let ancestors = tree.ancestors(of: process)
            guard !ancestors.contains(where: { rootNames.contains($0.name) || compilerNames.contains($0.name) })
            else { continue }
            let host = ancestors.last ?? process
            guard seenHosts.insert(host.pid).inserted else { continue }
            builds.append(ActiveBuild(pid: process.pid, kind: .other, source: source(of: ancestors)))
        }
        return builds
    }

    /// "AlphaBankRetail · build": the scheme (or workspace/project name) and the
    /// action, which xcodebuild defaults to `build`.
    static func xcodebuildDetail(_ args: [String]) -> String? {
        let container = xcodebuildContainer(args)
        let scheme = value(after: "-scheme", in: args) ?? container.map {
            (($0 as NSString).lastPathComponent as NSString).deletingPathExtension
        }
        guard let scheme else { return nil }
        let action = args.last(where: xcodebuildActions.contains) ?? "build"
        return "\(scheme) · \(action)"
    }

    /// The values of `xcodebuildPathFlags`, made absolute against the build's
    /// working directory (relative ones are dropped when it's unknown).
    static func xcodebuildPaths(_ args: [String], workingDirectory: String?) -> [String] {
        xcodebuildPathFlags.compactMap { value(after: $0, in: args) }
            .compactMap { absolute($0, in: workingDirectory) }
    }

    /// Where a `swift build/test/run` puts its products: `--scratch-path`
    /// (or the older `--build-path`), else `.build` in `--package-path` or the
    /// working directory.
    static func swiftPMPaths(_ args: [String], workingDirectory: String?) -> [String] {
        if let scratch = value(after: "--scratch-path", in: args) ?? value(after: "--build-path", in: args) {
            return absolute(scratch, in: workingDirectory).map { [$0] } ?? []
        }
        let package = value(after: "--package-path", in: args) ?? "."
        return absolute(package, in: workingDirectory)
            .map { [(($0 as NSString).appendingPathComponent(".build") as NSString).standardizingPath] } ?? []
    }

    /// Whether `args` has a path a working directory is needed to resolve.
    static func needsWorkingDirectory(_ process: RunningProcess, args: [String]) -> Bool {
        if process.name == "xcodebuild" {
            return xcodebuildContainer(args) == nil
                || xcodebuildPathFlags.compactMap({ value(after: $0, in: args) }).contains { !$0.hasPrefix("/") }
        }
        let explicit = value(after: "--scratch-path", in: args) ?? value(after: "--build-path", in: args)
            ?? value(after: "--package-path", in: args)
        return !(explicit?.hasPrefix("/") ?? false)
    }

    private static func absolute(_ path: String, in directory: String?) -> String? {
        if path.hasPrefix("/") { return (path as NSString).standardizingPath }
        guard let directory else { return nil }
        return ((directory as NSString).appendingPathComponent(path) as NSString).standardizingPath
    }

    /// `roots` plus every process below them.
    static func processTreePIDs(of roots: [Int32], in processes: [RunningProcess]) -> [Int32] {
        var children: [Int32: [Int32]] = [:]
        for process in processes { children[process.ppid, default: []].append(process.pid) }
        var result: [Int32] = []
        var seen: Set<Int32> = []
        var stack = roots
        while let pid = stack.popLast() {
            guard seen.insert(pid).inserted else { continue }
            result.append(pid)
            stack.append(contentsOf: children[pid] ?? [])
        }
        return result
    }

    /// File paths (`n/…` lines) from `lsof -Fn` output.
    static func parseOpenFiles(_ output: String) -> [String] {
        output.split(separator: "\n").compactMap { line in
            line.hasPrefix("n/") ? String(line.dropFirst()) : nil
        }
    }

    /// The `-workspace` or `-project` path, as passed (may be relative).
    static func xcodebuildContainer(_ args: [String]) -> String? {
        value(after: "-workspace", in: args) ?? value(after: "-project", in: args)
    }

    private static func value(after flag: String, in args: [String]) -> String? {
        guard let index = args.firstIndex(of: flag), args.indices.contains(index + 1) else { return nil }
        return args[index + 1]
    }

    /// Names the tool or app that launched a build: the nearest recognizable
    /// tool in the ancestor chain, else the top-level app hosting it.
    static func source(of ancestors: [RunningProcess]) -> String {
        for ancestor in ancestors {
            if let known = knownTool(ancestor) { return known }
        }
        guard let host = ancestors.last else { return "Unknown" }
        return appName(in: host.path) ?? host.name
    }

    private static func knownTool(_ process: RunningProcess) -> String? {
        let path = process.path.lowercased()
        if path.contains("xcodebuildmcp") { return "XcodeBuildMCP" }
        if path.contains("fastlane") { return "fastlane" }
        if path.contains("tuist") { return "Tuist" }
        if process.name == "claude" { return "Claude Code" }
        if let app = appName(in: process.path), app.hasPrefix("Xcode"),
           process.path.hasSuffix("/Contents/MacOS/Xcode") {
            return "Xcode"
        }
        return nil
    }

    /// "/Applications/Ghostty.app/Contents/MacOS/ghostty" → "Ghostty".
    private static func appName(in path: String) -> String? {
        guard let component = path.split(separator: "/").first(where: { $0.hasSuffix(".app") })
        else { return nil }
        return String(component.dropLast(4))
    }

    /// "XcodeBuildMCP ×2, Xcode" — sources in order of first appearance.
    static func summary(_ builds: [ActiveBuild]) -> String {
        var order: [String] = []
        var counts: [String: Int] = [:]
        for build in builds {
            if counts[build.source] == nil { order.append(build.source) }
            counts[build.source, default: 0] += 1
        }
        return order.map { source in
            let count = counts[source] ?? 1
            return count > 1 ? "\(source) ×\(count)" : source
        }.joined(separator: ", ")
    }
}

private struct ProcessTree {
    private let byPID: [Int32: RunningProcess]
    private let parentsWithChildren: Set<Int32>

    init(_ processes: [RunningProcess]) {
        byPID = Dictionary(processes.map { ($0.pid, $0) }, uniquingKeysWith: { first, _ in first })
        parentsWithChildren = Set(processes.map(\.ppid))
    }

    /// Nearest parent first, stopping before launchd (pid 1).
    func ancestors(of process: RunningProcess) -> [RunningProcess] {
        var result: [RunningProcess] = []
        var visited: Set<Int32> = [process.pid]
        var current = process.ppid
        while current > 1, visited.insert(current).inserted, let parent = byPID[current] {
            result.append(parent)
            current = parent.ppid
        }
        return result
    }

    func hasChildren(_ process: RunningProcess) -> Bool {
        parentsWithChildren.contains(process.pid)
    }
}

protocol BuildDetecting: Sendable {
    func activeBuilds() async throws -> [ActiveBuild]
    /// Normalized paths (see `PathsInUse`) that running builds are using; a
    /// clean leaves the entries holding them alone.
    func pathsInUse() async throws -> Set<String>
}

extension BuildDetecting {
    func pathsInUse() async throws -> Set<String> {
        Set(try await activeBuilds().flatMap(\.paths).map(PathsInUse.normalize))
    }
}

struct BuildDetector: BuildDetecting {
    let runner: CommandRunning

    init(runner: CommandRunning = CommandRunner()) {
        self.runner = runner
    }

    func activeBuilds() async throws -> [ActiveBuild] {
        try await snapshot().builds
    }

    /// The folders on each build's command line plus every file its process
    /// tree (build service, compilers, linkers…) has open right now. Only paths
    /// under the home folder are kept — every cleanup target lives there.
    func pathsInUse() async throws -> Set<String> {
        let (processes, builds) = try await snapshot()
        var paths = builds.flatMap(\.paths)
        let pids = BuildDetection.processTreePIDs(of: builds.map(\.pid), in: processes)
        if !pids.isEmpty {
            // lsof exits non-zero when a pid has exited meanwhile; what it
            // printed for the others is still valid.
            let args = ["-n", "-P", "-w", "-Fn", "-p", pids.map(String.init).joined(separator: ",")]
            if let output = try? await runner.run("/usr/sbin/lsof", args) {
                paths += BuildDetection.parseOpenFiles(String(decoding: output.stdout, as: UTF8.self))
            }
        }
        let home = PathsInUse.normalize(NSHomeDirectory()) + "/"
        return Set(paths.map(PathsInUse.normalize).filter { $0.hasPrefix(home) })
    }

    private func snapshot() async throws -> (processes: [RunningProcess], builds: [ActiveBuild]) {
        let (status, data, _) = try await runner.run("/bin/ps", ["-axww", "-o", "pid=,ppid=,comm="])
        guard status == 0 else { throw ProcessError.process("ps exited with \(status)") }
        let processes = BuildDetection.parseProcesses(String(decoding: data, as: UTF8.self))

        // Arguments only for xcodebuild (to skip read-only queries and read the
        // folders it uses) and SwiftPM (to find its .build).
        let candidates = processes.filter {
            $0.name == "xcodebuild" || BuildDetection.swiftPMNames.contains($0.name)
        }
        var arguments: [Int32: [String]] = [:]
        if !candidates.isEmpty {
            let args = ["-ww", "-o", "pid=,args=", "-p", candidates.map { String($0.pid) }.joined(separator: ",")]
            if let output = try? await runner.run("/bin/ps", args) {
                arguments = BuildDetection.parseArguments(String(decoding: output.stdout, as: UTF8.self))
            }
        }
        // Relative or missing paths: resolve against the build's working
        // directory (looked up only in that case — lsof is slow-ish).
        var workingDirectories: [Int32: String] = [:]
        for process in candidates {
            guard let args = arguments[process.pid],
                  BuildDetection.needsWorkingDirectory(process, args: args) else { continue }
            workingDirectories[process.pid] = await workingDirectory(of: process.pid)
        }
        let builds = BuildDetection.detect(processes: processes, arguments: arguments,
                                           workingDirectories: workingDirectories,
                                           ignoringDescendantsOf: ProcessInfo.processInfo.processIdentifier) { pid, container in
            let directory: String? = if let container, container.hasPrefix("/") {
                container
            } else if let cwd = workingDirectories[pid] {
                container.map { (cwd as NSString).appendingPathComponent($0) } ?? cwd
            } else {
                nil
            }
            guard let directory else { return nil }
            return GitBranch.name(containing: directory) ?? GitBranch.folderName(of: directory)
        }
        return (processes, builds)
    }

    /// The process's current directory, via `lsof -a -p PID -d cwd -Fn`.
    private func workingDirectory(of pid: Int32) async -> String? {
        guard let output = try? await runner.run("/usr/sbin/lsof", ["-a", "-p", String(pid), "-d", "cwd", "-Fn"])
        else { return nil }
        return String(decoding: output.stdout, as: UTF8.self)
            .split(separator: "\n")
            .first { $0.hasPrefix("n/") }
            .map { String($0.dropFirst()) }
    }
}
