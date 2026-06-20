import XCTest
@testable import XcodeCleaner

final class CleanerTests: XCTestCase {
    func testRemoveDirectoryContentsLeavesDirEmpty() throws {
        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        try "x".write(to: dir.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
        try fm.createDirectory(at: dir.appendingPathComponent("sub"), withIntermediateDirectories: true)

        try Cleaner().removeDirectoryContents(dir.path)

        XCTAssertTrue(fm.fileExists(atPath: dir.path))
        XCTAssertEqual(try fm.contentsOfDirectory(atPath: dir.path), [])
    }
}
