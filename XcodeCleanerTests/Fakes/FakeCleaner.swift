import Foundation
import os
@testable import XcodeCleaner

final class FakeCleaner: Cleaning, @unchecked Sendable {
    private let lock = OSAllocatedUnfairLock()
    private let result: Result<Void, Error>
    private var _cleanedNames: [String] = []

    init(result: Result<Void, Error>) { self.result = result }

    var cleanedNames: [String] { lock.withLock { _cleanedNames } }

    func clean(_ target: CleanupTarget) async -> Result<Void, Error> {
        let name = target.name
        lock.withLock { _cleanedNames.append(name) }
        return result
    }
}
