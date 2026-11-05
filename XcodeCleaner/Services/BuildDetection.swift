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
        "-checkFirstLaunchStatus",
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

    static func detect(processes: [RunningProcess], arguments: [Int32: [String]] = [:],
                       branch resolveBranch: BranchResolver = { _, _ in nil }) -> [ActiveBuild] {
        let tree = ProcessTree(processes)
        var builds: [ActiveBuild] = []

        for process in processes where process.name == "xcodebuild" {
            let ancestors = tree.ancestors(of: process)
            guard !ancestors.contains(where: { $0.name == "xcodebuild" }) else { continue }
            if let args = arguments[process.pid], args.contains(where: queryFlags.contains) { continue }
            let args = arguments[process.pid] ?? []
            builds.append(ActiveBuild(pid: process.pid, kind: .xcodebuild, source: source(of: ancestors),
                                      detail: xcodebuildDetail(args),
                                      branch: resolveBranch(process.pid, xcodebuildContainer(args))))
        }

        for process in processes where swiftPMNames.contains(process.name) {
            let ancestors = tree.ancestors(of: process)
            guard !ancestors.contains(where: { swiftPMNames.contains($0.name) }) else { continue }
            builds.append(ActiveBuild(pid: process.pid, kind: .swiftPM, source: source(of: ancestors)))
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
}

struct BuildDetector: BuildDetecting {
    let runner: CommandRunning

    init(runner: CommandRunning = CommandRunner()) {
        self.runner = runner
    }

    func activeBuilds() async throws -> [ActiveBuild] {
        let (status, data, _) = try await runner.run("/bin/ps", ["-axww", "-o", "pid=,ppid=,comm="])
        guard status == 0 else { throw ProcessError.process("ps exited with \(status)") }
        let processes = BuildDetection.parseProcesses(String(decoding: data, as: UTF8.self))

        // Fetch arguments only for xcodebuild, to skip read-only queries.
        let pids: [String] = processes.filter { $0.name == "xcodebuild" }.map { String($0.pid) }
        var arguments: [Int32: [String]] = [:]
        if !pids.isEmpty {
            let args = ["-ww", "-o", "pid=,args=", "-p", pids.joined(separator: ",")]
            if let output = try? await runner.run("/bin/ps", args) {
                arguments = BuildDetection.parseArguments(String(decoding: output.stdout, as: UTF8.self))
            }
        }
        // Relative or missing -workspace/-project: resolve against the build's
        // working directory (looked up only in that case — lsof is slow-ish).
        var workingDirectories: [Int32: String] = [:]
        for (pid, args) in arguments where !(BuildDetection.xcodebuildContainer(args)?.hasPrefix("/") ?? false) {
            workingDirectories[pid] = await workingDirectory(of: pid)
        }
        return BuildDetection.detect(processes: processes, arguments: arguments) { pid, container in
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
