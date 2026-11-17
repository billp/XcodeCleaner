import XCTest
@testable import XcodeCleaner

final class BuildDetectionTests: XCTestCase {
    private let xcodebuild = "/Applications/Xcode-26.6.0.app/Contents/Developer/usr/bin/xcodebuild"
    private let buildService = "/Applications/Xcode-26.6.0.app/Contents/SharedFrameworks/SwiftBuild.framework"
        + "/Versions/A/PlugIns/SWBBuildService.bundle/Contents/MacOS/SWBBuildService"
    private let mcpNode = "/opt/homebrew/Cellar/xcodebuildmcp/2.7.0/libexec/node-runtime"
    private let xcodeApp = "/Applications/Xcode-26.6.0.app/Contents/MacOS/Xcode"

    private func p(_ pid: Int32, _ ppid: Int32, _ path: String) -> RunningProcess {
        RunningProcess(pid: pid, ppid: ppid, path: path)
    }

    func testParsesPathsWithSpaces() {
        let output = """
          123     1 /Applications/Xcode 2.app/Contents/MacOS/Xcode
          456   123 /usr/bin/clang
        garbage line
        """
        XCTAssertEqual(BuildDetection.parseProcesses(output), [
            p(123, 1, "/Applications/Xcode 2.app/Contents/MacOS/Xcode"),
            p(456, 123, "/usr/bin/clang"),
        ])
    }

    func testParsesArguments() {
        let args = BuildDetection.parseArguments("  71200 /usr/bin/xcodebuild -list -json\n")
        XCTAssertEqual(args[71200], ["/usr/bin/xcodebuild", "-list", "-json"])
    }

    /// Snapshot of a real machine: two XcodeBuildMCP sessions inside Claude Code,
    /// each running an xcodebuild whose build service runs plugin tools.
    func testDetectsXcodeBuildMCPBuildsOnce() {
        let processes = [
            p(23400, 22440, "/Users/me/.local/bin/claude"),
            p(70345, 23400, "/bin/zsh"),
            p(70355, 70345, mcpNode),
            p(71200, 70355, xcodebuild),
            p(83414, 71200, buildService),
            p(94988, 83414, "/Users/me/DerivedData/xcstrings-tool"),
            p(71600, 30675, mcpNode),
            p(72938, 71600, xcodebuild),
            p(92248, 72938, buildService),
        ]
        let builds = BuildDetection.detect(processes: processes)
        XCTAssertEqual(builds.map(\.pid), [71200, 72938])
        XCTAssertEqual(Set(builds.map(\.kind)), [.xcodebuild])
        XCTAssertEqual(Set(builds.map(\.source)), ["XcodeBuildMCP"])
        XCTAssertEqual(BuildDetection.summary(builds), "XcodeBuildMCP ×2")
    }

    func testXcodebuildQueriesAreNotBuilds() {
        let processes = [p(10, 1, "/bin/zsh"), p(11, 10, xcodebuild)]
        let builds = BuildDetection.detect(processes: processes,
                                           arguments: [11: [xcodebuild, "-showBuildSettings", "-json"]])
        XCTAssertTrue(builds.isEmpty)
    }

    /// `xcrun simctl` runs Xcode's simctl shim, which itself calls
    /// `xcodebuild -sdk … -find …` and `xcodebuild -runFirstLaunch`.
    func testSimctlShimLookupsAreNotBuilds() {
        let processes = [p(10, 1, "/bin/zsh"), p(11, 10, xcodebuild), p(12, 10, xcodebuild)]
        let builds = BuildDetection.detect(processes: processes, arguments: [
            11: [xcodebuild, "-sdk", "/Applications/Xcode.app/.../MacOSX.sdk", "-find", "simctl"],
            12: [xcodebuild, "-runFirstLaunch"],
        ])
        XCTAssertTrue(builds.isEmpty)
    }

    /// Anything Xcode Cleaner launches itself (scans via xcrun/simctl…) is
    /// never a build, whatever its arguments.
    func testProcessesLaunchedByThisAppAreNotBuilds() {
        let app = "/Applications/XcodeCleaner.app/Contents/MacOS/XcodeCleaner"
        let processes = [
            p(1095, 1, app),
            p(2000, 1095, "/usr/bin/xcrun"),
            p(2001, 2000, xcodebuild),
            p(2002, 2001, "/usr/bin/clang"),
        ]
        XCTAssertTrue(BuildDetection.detect(processes: processes, ignoringDescendantsOf: 1095).isEmpty)
    }

    func testXcodebuildPathsAreMadeAbsolute() {
        let args = [xcodebuild, "-workspace", "App.xcworkspace", "-scheme", "App",
                    "-derivedDataPath", "/Users/me/ws/wt-1/DerivedData", "-resultBundlePath", "../out.xcresult", "test"]
        XCTAssertEqual(BuildDetection.xcodebuildPaths(args, workingDirectory: "/Users/me/src"), [
            "/Users/me/src/App.xcworkspace", "/Users/me/ws/wt-1/DerivedData", "/Users/me/out.xcresult",
        ])
        XCTAssertEqual(BuildDetection.xcodebuildPaths(args, workingDirectory: nil), ["/Users/me/ws/wt-1/DerivedData"])
    }

    func testSwiftPMPathsPointAtItsBuildFolder() {
        XCTAssertEqual(BuildDetection.swiftPMPaths([], workingDirectory: "/Users/me/Pkg"), ["/Users/me/Pkg/.build"])
        XCTAssertEqual(BuildDetection.swiftPMPaths(["--package-path", "/p/Q"], workingDirectory: nil), ["/p/Q/.build"])
        XCTAssertEqual(BuildDetection.swiftPMPaths(["--scratch-path", "/tmp/s"], workingDirectory: nil), ["/tmp/s"])
        XCTAssertEqual(BuildDetection.swiftPMPaths([], workingDirectory: nil), [])
    }

    func testDetectionAttachesPaths() {
        let processes = [p(10, 1, "/bin/zsh"), p(11, 10, xcodebuild), p(12, 10, "/usr/bin/swift-build")]
        let builds = BuildDetection.detect(
            processes: processes,
            arguments: [11: [xcodebuild, "-testProductsPath", "/Users/me/ws/wt-1/tp.xctestproducts"],
                        12: ["/usr/bin/swift-build"]],
            workingDirectories: [12: "/Users/me/Pkg"])
        XCTAssertEqual(builds.map(\.paths), [["/Users/me/ws/wt-1/tp.xctestproducts"], ["/Users/me/Pkg/.build"]])
    }

    func testProcessTreePIDsIncludesEveryDescendant() {
        let processes = [p(11, 1, xcodebuild), p(12, 11, buildService), p(13, 12, "/usr/bin/clang"),
                         p(20, 1, "/bin/zsh")]
        XCTAssertEqual(Set(BuildDetection.processTreePIDs(of: [11], in: processes)), [11, 12, 13])
    }

    func testParsesOpenFiles() {
        let output = "p11\nfcwd\nn/Users/me/src\nf3\nn/Users/me/dd/build.db\nf4\nnpipe\n"
        XCTAssertEqual(BuildDetection.parseOpenFiles(output), ["/Users/me/src", "/Users/me/dd/build.db"])
    }

    func testXcodebuildFromTerminalIsAttributedToTerminal() {
        let processes = [
            p(5, 1, "/System/Applications/Utilities/Terminal.app/Contents/MacOS/Terminal"),
            p(6, 5, "/usr/bin/login"),
            p(7, 6, "/bin/zsh"),
            p(8, 7, xcodebuild),
        ]
        XCTAssertEqual(BuildDetection.detect(processes: processes),
                       [ActiveBuild(pid: 8, kind: .xcodebuild, source: "Terminal")])
    }

    func testIdleXcodeBuildServiceIsNotABuild() {
        let processes = [p(100, 1, xcodeApp), p(101, 100, buildService)]
        XCTAssertTrue(BuildDetection.detect(processes: processes).isEmpty)
    }

    func testBusyXcodeBuildServiceIsAnXcodeBuild() {
        let processes = [
            p(100, 1, xcodeApp),
            p(101, 100, buildService),
            p(102, 101, "/Applications/Xcode-26.6.0.app/Contents/Developer/Toolchains/swift-frontend"),
        ]
        XCTAssertEqual(BuildDetection.detect(processes: processes),
                       [ActiveBuild(pid: 101, kind: .xcode, source: "Xcode")])
    }

    func testSwiftPMBuildCountsOnce() {
        let processes = [
            p(1, 0, "/sbin/launchd"),
            p(200, 1, "/Applications/Ghostty.app/Contents/MacOS/ghostty"),
            p(201, 200, "/bin/zsh"),
            p(202, 201, "/usr/bin/swift-build"),
            p(203, 202, "/usr/bin/swift-frontend"),
            p(204, 202, "/usr/bin/swift-frontend"),
        ]
        XCTAssertEqual(BuildDetection.detect(processes: processes),
                       [ActiveBuild(pid: 202, kind: .swiftPM, source: "Ghostty")])
    }

    func testStrayCompilersGroupPerHostApp() {
        let processes = [
            p(300, 1, "/Applications/iTerm.app/Contents/MacOS/iTerm2"),
            p(301, 300, "/usr/bin/make"),
            p(302, 301, "/usr/bin/clang"),
            p(303, 302, "/usr/bin/ld"),     // child of a compiler: same build
            p(304, 301, "/usr/bin/clang"),  // same host: same build
        ]
        XCTAssertEqual(BuildDetection.detect(processes: processes),
                       [ActiveBuild(pid: 302, kind: .other, source: "iTerm")])
    }

    func testUnrelatedProcessesAreIgnored() {
        let processes = [p(400, 1, "/Applications/Photos.app/Contents/MacOS/Photos"), p(401, 400, "/bin/zsh")]
        XCTAssertTrue(BuildDetection.detect(processes: processes).isEmpty)
    }

    func testDetectorReadsPsOutput() async throws {
        let runner = FakeCommandRunner(responses: [
            .init(status: 0, stdout: Data("10 1 /bin/zsh\n11 10 \(xcodebuild)\n".utf8), stderr: Data()),
            .init(status: 0, stdout: Data("11 \(xcodebuild) -scheme App build\n".utf8), stderr: Data()),
        ])
        let builds = try await BuildDetector(runner: runner).activeBuilds()
        XCTAssertEqual(builds.map(\.pid), [11])
        XCTAssertEqual(runner.calls[1].args.last, "11")
    }
}

@MainActor
final class CleanConfirmationTests: XCTestCase {
    private func waitUntil(timeout: TimeInterval = 2.0, _ cond: () -> Bool) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !cond() && Date() < deadline {
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
    }

    private func makeVM(_ detector: FakeBuildDetector, cleaner: FakeCleaner) -> CleanerViewModel {
        CleanerViewModel(scanner: FakeScanner(result: .success(100)),
                         cleaner: cleaner,
                         availability: FakeAvailability(existsResult: false),
                         fullDiskAccess: FakeFullDiskAccess(granted: true),
                         diskSpace: FakeDiskSpace(),
                         buildDetector: detector)
    }

    func testCleansImmediatelyWithoutBuilds() async {
        let cleaner = FakeCleaner(result: .success(()))
        let vm = makeVM(.idle, cleaner: cleaner)
        await vm.requestClean(vm.targets[0])
        await waitUntil { cleaner.cleanedKinds.count == 1 }
        XCTAssertEqual(cleaner.cleanedKinds.count, 1)
        XCTAssertNil(vm.pendingClean)
    }

    func testAsksForConfirmationWhileBuilding() async {
        let cleaner = FakeCleaner(result: .success(()))
        let vm = makeVM(.busy, cleaner: cleaner)
        await vm.requestClean(vm.targets[0])
        XCTAssertNotNil(vm.pendingClean)
        XCTAssertEqual(vm.activeBuilds, [FakeBuildDetector.sampleBuild])
        try? await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertTrue(cleaner.cleanedKinds.isEmpty)

        vm.confirmPendingClean()
        await waitUntil { cleaner.cleanedKinds.count == 1 }
        XCTAssertEqual(cleaner.cleanedKinds, [vm.targets[0].kind])
        XCTAssertNil(vm.pendingClean)
    }

    func testCancelDiscardsPendingCleanAll() async {
        let cleaner = FakeCleaner(result: .success(()))
        let vm = makeVM(.busy, cleaner: cleaner)
        await vm.requestCleanAll()
        guard case .all = vm.pendingClean else { return XCTFail("expected pending Clean All") }
        vm.cancelPendingClean()
        XCTAssertNil(vm.pendingClean)
        try? await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertTrue(cleaner.cleanedKinds.isEmpty)
    }
}

final class XcodebuildDetailTests: XCTestCase {
    func testDetailShowsSchemeAndAction() {
        let args = ["/usr/bin/xcodebuild", "-workspace", "/src/worktrees/lively-rocket/App.xcworkspace",
                    "-scheme", "App", "-destination", "platform=iOS", "Simulator,id=X", "build-for-testing"]
        XCTAssertEqual(BuildDetection.xcodebuildDetail(args), "App · build-for-testing")
    }

    func testDetailDefaultsActionToBuildAndSchemeToProjectName() {
        let args = ["/usr/bin/xcodebuild", "-project", "/src/Tool/Tool.xcodeproj"]
        XCTAssertEqual(BuildDetection.xcodebuildDetail(args), "Tool · build")
    }

    func testDetailIsNilWithoutSchemeOrContainer() {
        XCTAssertNil(BuildDetection.xcodebuildDetail(["/usr/bin/xcodebuild", "build"]))
    }

    func testDetectionAttachesDetail() {
        let processes = [RunningProcess(pid: 10, ppid: 1, path: "/bin/zsh"),
                         RunningProcess(pid: 11, ppid: 10, path: "/usr/bin/xcodebuild")]
        let args = ["/usr/bin/xcodebuild", "-workspace", "/src/App.xcworkspace", "-scheme", "App", "test"]
        let builds = BuildDetection.detect(processes: processes, arguments: [11: args]) { pid, container in
            pid == 11 && container == "/src/App.xcworkspace" ? "feature/x" : nil
        }
        XCTAssertEqual(builds.first?.detail, "App · test")
        XCTAssertEqual(builds.first?.branch, "feature/x")
    }
}

final class GitBranchTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("gitbranch-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func write(_ text: String, to relative: String) throws {
        let url = root.appendingPathComponent(relative)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    func testReadsBranchFromRepoAboveWorkspace() throws {
        try write("ref: refs/heads/feature/banner-carousel\n", to: "repo/.git/HEAD")
        try FileManager.default.createDirectory(at: root.appendingPathComponent("repo/App/App.xcworkspace"),
                                                withIntermediateDirectories: true)
        let workspace = root.appendingPathComponent("repo/App/App.xcworkspace").path
        XCTAssertEqual(GitBranch.name(containing: workspace), "feature/banner-carousel")
    }

    func testReadsBranchFromLinkedWorktree() throws {
        try write("ref: refs/heads/bug/terms\n", to: "repo/.git/worktrees/wt/HEAD")
        try write("gitdir: \(root.path)/repo/.git/worktrees/wt\n", to: "wt/.git")
        XCTAssertEqual(GitBranch.name(containing: root.appendingPathComponent("wt/App.xcworkspace").path),
                       "bug/terms")
    }

    func testDetachedHeadShowsShortHash() {
        XCTAssertEqual(GitBranch.parseHead("84134b1f00d1e5bd2a43c3f3b1f6c0a4a0e8d9c1\n"), "84134b1")
    }

    func testNoRepoReturnsNil() {
        XCTAssertNil(GitBranch.name(containing: root.appendingPathComponent("nowhere").path))
    }

    func testFolderNameFallback() {
        XCTAssertEqual(GitBranch.folderName(of: "/src/my-checkout/App.xcworkspace"), "my-checkout")
        XCTAssertEqual(GitBranch.folderName(of: "/src/my-checkout"), "my-checkout")
    }
}
