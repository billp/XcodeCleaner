import XCTest
@testable import XcodeCleaner

final class SimctlParsingTests: XCTestCase {
    func testPlaceholder() { XCTAssertTrue(true) }

    func testSizeTextFormatsScannedBytes() {
        let t = CleanupTarget(name: "X", kind: .unavailableSimulators)
        t.state = .scanned(1_500_000_000)
        XCTAssertEqual(t.sizeBytes, 1_500_000_000)
        XCTAssertTrue(t.sizeText.contains("GB"))
    }

    func testSizeTextIdleAndScanning() {
        let t = CleanupTarget(name: "X", kind: .unavailableSimulators)
        XCTAssertEqual(t.sizeText, "—")
        t.state = .scanning
        XCTAssertEqual(t.sizeText, "scanning…")
    }
}
