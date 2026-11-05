import Foundation

/// Why an unattended clean is running.
enum AutoCleanTrigger: Equatable, Sendable {
    case scheduled
    case lowDisk
}
