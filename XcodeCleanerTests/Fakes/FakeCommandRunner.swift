import Foundation
import os
@testable import XcodeCleaner

final class FakeCommandRunner: CommandRunning, @unchecked Sendable {
    struct Response { let status: Int32; let stdout: Data; let stderr: Data }

    private let lock = OSAllocatedUnfairLock()
    private var _responses: [Response] = []
    private var _calls: [(launchPath: String, args: [String])] = []

    init(responses: [Response]) {
        _responses = responses
    }

    convenience init(status: Int32 = 0, stdout: Data = Data(), stderr: Data = Data()) {
        self.init(responses: [Response(status: status, stdout: stdout, stderr: stderr)])
    }

    var calls: [(launchPath: String, args: [String])] {
        lock.withLock { _calls }
    }

    func run(_ launchPath: String, _ args: [String]) async throws
        -> (status: Int32, stdout: Data, stderr: Data) {
        lock.withLock {
            _calls.append((launchPath, args))
            let r = _responses.count > 1 ? _responses.removeFirst()
                : (_responses.first ?? Response(status: 0, stdout: Data(), stderr: Data()))
            return (r.status, r.stdout, r.stderr)
        }
    }
}
