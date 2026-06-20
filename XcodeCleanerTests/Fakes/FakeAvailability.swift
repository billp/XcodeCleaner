import Foundation
@testable import XcodeCleaner

final class FakeAvailability: AvailabilityChecking, @unchecked Sendable {
    private let existsResult: Bool

    init(existsResult: Bool) {
        self.existsResult = existsResult
    }

    func exists(_ path: String) -> Bool {
        existsResult
    }
}
