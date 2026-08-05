import Foundation
@testable import XcodeCleaner

final class FakeFullDiskAccess: FullDiskAccessChecking, @unchecked Sendable {
    private let granted: Bool

    init(granted: Bool) {
        self.granted = granted
    }

    func isGranted() -> Bool {
        granted
    }
}
