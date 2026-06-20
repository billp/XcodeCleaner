import Foundation
import os
@testable import XcodeCleaner

final class FakeNotifier: Notifying, @unchecked Sendable {
    private let lock = OSAllocatedUnfairLock()
    private var _authCount = 0
    private var _finished: [(count: Int, bytes: Int64)] = []

    var authorizationRequests: Int { lock.withLock { _authCount } }
    var finishedCalls: [(count: Int, bytes: Int64)] { lock.withLock { _finished } }

    func requestAuthorization() async { lock.withLock { _authCount += 1 } }

    func notifyCleanFinished(targetCount: Int, reclaimedBytes: Int64) async {
        lock.withLock { _finished.append((targetCount, reclaimedBytes)) }
    }
}
