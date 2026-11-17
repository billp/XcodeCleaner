import XCTest
@testable import XcodeCleaner

final class PathsInUseTests: XCTestCase {
    private let fm = FileManager.default
    private var base: String!

    override func setUpWithError() throws {
        base = PathsInUse.normalize(fm.temporaryDirectory.appendingPathComponent(UUID().uuidString).path)
        try fm.createDirectory(atPath: base, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? fm.removeItem(atPath: base)
    }

    private func path(_ relative: String) -> String { (base as NSString).appendingPathComponent(relative) }

    func testEntryHoldingAPathInUseIsInUse() {
        let entry = path("workspaces/wt-1")
        XCTAssertTrue(PathsInUse.isInUse(entry, paths: [path("workspaces/wt-1/DerivedData")]))
        XCTAssertTrue(PathsInUse.isInUse(entry, paths: [entry]))
    }

    func testSiblingWithSharedPrefixIsNotInUse() {
        XCTAssertFalse(PathsInUse.isInUse(path("workspaces/wt-1"), paths: [path("workspaces/wt-10/DerivedData")]))
    }

    /// A build's working directory or the root of the target must not spare
    /// everything below it.
    func testPathAboveEntryDoesNotSpareIt() {
        XCTAssertFalse(PathsInUse.isInUse(path("DerivedData/App-abc"), paths: [base, path("DerivedData")]))
    }

    func testNothingInUseSparesNothing() {
        XCTAssertFalse(PathsInUse.isInUse(path("anything"), paths: []))
    }

    func testDerivedDataFolderOfWorkspaceBeingBuiltIsInUse() throws {
        let entry = path("DerivedData/App-abc")
        try fm.createDirectory(atPath: entry, withIntermediateDirectories: true)
        let workspace = path("src/App.xcworkspace")
        let plist = try PropertyListSerialization.data(fromPropertyList: ["WorkspacePath": workspace],
                                                       format: .xml, options: 0)
        try plist.write(to: URL(fileURLWithPath: (entry as NSString).appendingPathComponent("info.plist")))

        XCTAssertTrue(PathsInUse.isInUse(entry, paths: [workspace]))
        XCTAssertFalse(PathsInUse.isInUse(entry, paths: [path("src/Other.xcworkspace")]))
    }

    func testSharedCachesAreSparedWhileTheirDerivedDataIsInUse() {
        let moduleCache = path("DerivedData/ModuleCache.noindex")
        XCTAssertTrue(PathsInUse.isInUse(moduleCache, paths: [path("DerivedData/App-abc/Build/x.o")]))
        XCTAssertFalse(PathsInUse.isInUse(moduleCache, paths: [path("elsewhere/x.o")]))
    }

    func testNormalizeResolvesSymlinksAndTrailingSlash() {
        XCTAssertEqual(PathsInUse.normalize("/tmp/"), PathsInUse.normalize("/private/tmp"))
        XCTAssertEqual(PathsInUse.normalize("/a/b/../c/"), "/a/c")
    }
}
