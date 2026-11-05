import Foundation
import os
@testable import XcodeCleaner

final class FakeDiskSpace: DiskSpaceProviding, @unchecked Sendable {
    private let lock = OSAllocatedUnfairLock()
    private var _space: DiskSpace?

    init(available: Int64 = 500, total: Int64 = 1000) {
        _space = DiskSpace(availableBytes: available, totalBytes: total)
    }

    var space: DiskSpace? {
        get { lock.withLock { _space } }
        set { lock.withLock { _space = newValue } }
    }

    func current() -> DiskSpace? { space }
}
