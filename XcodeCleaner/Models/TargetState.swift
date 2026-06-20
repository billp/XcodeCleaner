import Foundation

enum TargetState: Equatable {
    case idle
    case scanning
    case scanned(Int64)
    case cleaning
    case cleaned(Int64)
    case error(String)
}
