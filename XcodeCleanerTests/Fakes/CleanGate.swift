import Foundation
import os
@testable import XcodeCleaner

/// A fake `Cleaning` conformer that signals when `clean(_:)` is entered and
/// suspends until `release()` is called. Use in tests that need to observe
/// transient in-flight busy state.
final class CleanGate: Cleaning, @unchecked Sendable {
    private let startedContinuationLock = OSAllocatedUnfairLock<CheckedContinuation<Void, Never>?>(initialState: nil)
    private let releaseContinuationLock = OSAllocatedUnfairLock<CheckedContinuation<Void, Never>?>(initialState: nil)
    private let startedLock = OSAllocatedUnfairLock<Bool>(initialState: false)
    private let releasedLock = OSAllocatedUnfairLock<Bool>(initialState: false)

    /// Called by the test to block until `clean(_:)` has been entered.
    func waitUntilStarted() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let alreadyStarted = startedLock.withLock { $0 }
            if alreadyStarted {
                continuation.resume()
            } else {
                startedContinuationLock.withLock { $0 = continuation }
            }
        }
    }

    /// Unblocks the in-flight `clean(_:)` call.
    func release() {
        releasedLock.withLock { $0 = true }
        let cont = releaseContinuationLock.withLock { stored -> CheckedContinuation<Void, Never>? in
            let c = stored
            stored = nil
            return c
        }
        cont?.resume()
    }

    func clean(_ target: CleanupTarget) async -> Result<Void, Error> {
        // Signal that we've started.
        startedLock.withLock { $0 = true }
        let startCont = startedContinuationLock.withLock { stored -> CheckedContinuation<Void, Never>? in
            let c = stored
            stored = nil
            return c
        }
        startCont?.resume()

        // Wait until release() is called.
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let alreadyReleased = releasedLock.withLock { $0 }
            if alreadyReleased {
                continuation.resume()
            } else {
                releaseContinuationLock.withLock { $0 = continuation }
            }
        }

        return .success(())
    }
}
