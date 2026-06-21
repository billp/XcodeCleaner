import Foundation
import os
@testable import XcodeCleaner

final class FakeCleaner: Cleaning, @unchecked Sendable {
    private let lock = OSAllocatedUnfairLock()
    private let result: Result<Void, Error>
    private var _cleanedKinds: [CleanupKind] = []

    init(result: Result<Void, Error>) { self.result = result }

    var cleanedKinds: [CleanupKind] { lock.withLock { _cleanedKinds } }

    func clean(_ kind: CleanupKind) async -> Result<Void, Error> {
        lock.withLock { _cleanedKinds.append(kind) }
        return result
    }
}
