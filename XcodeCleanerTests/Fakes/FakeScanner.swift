import Foundation
import os
@testable import XcodeCleaner

final class FakeScanner: DiskScanning, @unchecked Sendable {
    private let lock = OSAllocatedUnfairLock()
    private var _results: [Result<Int64, Error>]
    private var _scannedNames: [String] = []

    init(result: Result<Int64, Error>) { self._results = [result] }
    init(results: [Result<Int64, Error>]) { self._results = results }

    var scannedNames: [String] { lock.withLock { _scannedNames } }

    func size(of target: CleanupTarget) async -> Result<Int64, Error> {
        let name = target.name
        return lock.withLock {
            _scannedNames.append(name)
            if _results.count > 1 { return _results.removeFirst() }
            return _results.first ?? .success(0)
        }
    }
}
