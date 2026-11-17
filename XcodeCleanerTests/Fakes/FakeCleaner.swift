import Foundation
import os
@testable import XcodeCleaner

final class FakeCleaner: Cleaning, @unchecked Sendable {
    private let lock = OSAllocatedUnfairLock()
    private let result: Result<Void, Error>
    private var _cleanedKinds: [CleanupKind] = []
    private var _sparedPaths: [Set<String>] = []

    init(result: Result<Void, Error>) { self.result = result }

    var cleanedKinds: [CleanupKind] { lock.withLock { _cleanedKinds } }
    /// The `sparing:` set passed with each clean, in call order.
    var sparedPaths: [Set<String>] { lock.withLock { _sparedPaths } }

    func clean(_ kind: CleanupKind) async -> Result<Void, Error> {
        await clean(kind, sparing: [])
    }

    func clean(_ kind: CleanupKind, sparing inUse: Set<String>) async -> Result<Void, Error> {
        lock.withLock {
            _cleanedKinds.append(kind)
            _sparedPaths.append(inUse)
        }
        return result
    }
}
