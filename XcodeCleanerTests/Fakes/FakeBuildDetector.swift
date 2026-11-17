import Foundation
import os
@testable import XcodeCleaner

/// Returns canned build lists; with several, each call consumes the next
/// (the last one repeats), mirroring `FakeCommandRunner`.
final class FakeBuildDetector: BuildDetecting, @unchecked Sendable {
    private let lock = OSAllocatedUnfairLock()
    private var _responses: [[ActiveBuild]]
    private var _callCount = 0
    private let paths: Set<String>?

    /// `paths` is what `pathsInUse()` returns; `nil` makes it throw.
    init(responses: [[ActiveBuild]], paths: Set<String>? = []) {
        _responses = responses
        self.paths = paths
    }
    convenience init(builds: [ActiveBuild] = [], paths: Set<String>? = []) {
        self.init(responses: [builds], paths: paths)
    }

    static var idle: FakeBuildDetector { FakeBuildDetector() }
    static var busy: FakeBuildDetector { FakeBuildDetector(builds: [sampleBuild]) }
    static let sampleBuild = ActiveBuild(pid: 42, kind: .xcodebuild, source: "XcodeBuildMCP")

    var callCount: Int { lock.withLock { _callCount } }

    func activeBuilds() async throws -> [ActiveBuild] {
        lock.withLock {
            _callCount += 1
            return _responses.count > 1 ? _responses.removeFirst() : (_responses.first ?? [])
        }
    }

    func pathsInUse() async throws -> Set<String> {
        guard let paths else { throw ProcessError.process("ps failed") }
        return paths
    }
}
