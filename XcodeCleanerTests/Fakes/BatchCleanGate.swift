import Foundation
@testable import XcodeCleaner

/// A `Cleaning` fake that suspends every `clean` call until `releaseAll()` is
/// called, so tests can observe a batch (e.g. Clean All) while it is in flight.
final class BatchCleanGate: Cleaning, @unchecked Sendable {
    private let lock = NSLock()
    private var _started = 0
    private var _released = false
    private var _continuations: [CheckedContinuation<Void, Never>] = []

    var startedCount: Int {
        lock.lock(); defer { lock.unlock() }
        return _started
    }

    func clean(_ target: CleanupTarget) async -> Result<Void, Error> {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            lock.lock()
            _started += 1
            if _released {
                lock.unlock()
                continuation.resume()
            } else {
                _continuations.append(continuation)
                lock.unlock()
            }
        }
        return .success(())
    }

    func releaseAll() {
        lock.lock()
        _released = true
        let pending = _continuations
        _continuations = []
        lock.unlock()
        for continuation in pending { continuation.resume() }
    }
}
