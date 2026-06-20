import Foundation
import os
@testable import XcodeCleaner

final class FakeScanner: DiskScanning, @unchecked Sendable {
    private let lock = OSAllocatedUnfairLock()
    private let result: Result<Int64, Error>
    private var _scannedNames: [String] = []

    init(result: Result<Int64, Error>) { self.result = result }

    var scannedNames: [String] { lock.withLock { _scannedNames } }

    func size(of target: CleanupTarget) async -> Result<Int64, Error> {
        let name = target.name
        lock.withLock { _scannedNames.append(name) }
        return result
    }
}
