import Foundation
import os
@testable import XcodeCleaner

final class FakeScanner: DiskScanning, @unchecked Sendable {
    private let lock = OSAllocatedUnfairLock()
    private var _results: [Result<Int64, Error>]

    init(result: Result<Int64, Error>) { self._results = [result] }
    init(results: [Result<Int64, Error>]) { self._results = results }

    func size(of kind: CleanupKind) async -> Result<Int64, Error> {
        lock.withLock {
            if _results.count > 1 { return _results.removeFirst() }
            return _results.first ?? .success(0)
        }
    }
}
