import Foundation

enum TargetState: Equatable {
    case idle
    case scanning
    case scanned(bytes: Int64)
    case cleaning
    case cleaned(bytes: Int64)
    case error(message: String)
}
