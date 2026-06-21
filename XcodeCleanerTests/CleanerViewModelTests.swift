import XCTest
@testable import XcodeCleaner

@MainActor
final class CleanerViewModelTests: XCTestCase {
    /// Polls until `cond` is true or the timeout elapses (ViewModel mutates state from an async Task).
    private func waitUntil(timeout: TimeInterval = 2.0, _ cond: () -> Bool) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !cond() && Date() < deadline {
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
    }

    func testScanSetsScannedBytes() async {
        let vm = CleanerViewModel(scanner: FakeScanner(result: .success(123)),
                                  cleaner: FakeCleaner(result: .success(())),
                                  availability: FakeAvailability(existsResult: true))
        let target = vm.targets[0]
        vm.scan(target)
        await waitUntil { if case .scanned = target.state { return true }; return false }
        XCTAssertEqual(target.sizeBytes, 123)
    }

    func testScanFailureSetsError() async {
        let vm = CleanerViewModel(scanner: FakeScanner(result: .failure(ScanError.process("x"))),
                                  cleaner: FakeCleaner(result: .success(())),
                                  availability: FakeAvailability(existsResult: true))
        let target = vm.targets[0]
        vm.scan(target)
        await waitUntil { if case .error = target.state { return true }; return false }
        if case .error = target.state {} else { XCTFail("expected .error state") }
    }

    func testCleanSetsCleanedBytes() async {
        let vm = CleanerViewModel(scanner: FakeScanner(result: .success(0)),
                                  cleaner: FakeCleaner(result: .success(())),
                                  availability: FakeAvailability(existsResult: true))
        let target = vm.targets[0]
        vm.clean(target)
        await waitUntil { if case .cleaned = target.state { return true }; return false }
        XCTAssertEqual(target.sizeBytes, 0)
    }

    func testCleanFailureSetsError() async {
        let vm = CleanerViewModel(scanner: FakeScanner(result: .success(0)),
                                  cleaner: FakeCleaner(result: .failure(ScanError.process("y"))),
                                  availability: FakeAvailability(existsResult: true))
        let target = vm.targets[0]
        vm.clean(target)
        await waitUntil { if case .error = target.state { return true }; return false }
        if case .error = target.state {} else { XCTFail("expected .error state") }
    }

    func testXcodeBuildMCPRowPresentWhenInstalled() {
        let vm = CleanerViewModel(scanner: FakeScanner(result: .success(0)),
                                  cleaner: FakeCleaner(result: .success(())),
                                  availability: FakeAvailability(existsResult: true))
        XCTAssertEqual(vm.targets.first?.name, "XcodeBuildMCP workspaces")
        XCTAssertTrue(vm.targets.contains { $0.name == "XcodeBuildMCP workspaces" })
    }

    func testXcodeBuildMCPRowAbsentWhenNotInstalled() {
        let vm = CleanerViewModel(scanner: FakeScanner(result: .success(0)),
                                  cleaner: FakeCleaner(result: .success(())),
                                  availability: FakeAvailability(existsResult: false))
        XCTAssertFalse(vm.targets.contains { $0.name == "XcodeBuildMCP workspaces" })
        XCTAssertEqual(vm.targets.first?.name, "Xcode DerivedData")
    }

    func testRunScheduledCleanReclaimsAndClearsFlag() async {
        let scanner = FakeScanner(results: [.success(1000), .success(0)]) // before, after
        let vm = CleanerViewModel(scanner: scanner,
                                  cleaner: FakeCleaner(result: .success(())),
                                  availability: FakeAvailability(existsResult: false))
        let name = vm.targets.first!.name
        let result = await vm.runScheduledClean(named: [name])
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.reclaimed, 1000)
        XCTAssertFalse(vm.isScheduledCleaning)
    }

    func testBusyStateReflectsManualCleaning() {
        let vm = CleanerViewModel(scanner: FakeScanner(result: .success(0)),
                                  cleaner: FakeCleaner(result: .success(())),
                                  availability: FakeAvailability(existsResult: false))
        XCTAssertFalse(vm.isManualCleaning)
        XCTAssertFalse(vm.isBusy)
        XCTAssertNil(vm.statusText)

        vm.targets[0].state = .cleaning
        XCTAssertTrue(vm.isManualCleaning)
        XCTAssertTrue(vm.isBusy)
        XCTAssertEqual(vm.statusText, "Cleaning…")

        vm.targets[0].state = .cleaned(0)
        XCTAssertFalse(vm.isBusy)
        XCTAssertNil(vm.statusText)
    }
}
