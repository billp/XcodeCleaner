import Foundation

protocol AvailabilityChecking: Sendable {
    func exists(_ path: String) -> Bool
}

struct AvailabilityChecker: AvailabilityChecking {
    func exists(_ path: String) -> Bool {
        FileManager.default.fileExists(atPath: path)
    }
}
