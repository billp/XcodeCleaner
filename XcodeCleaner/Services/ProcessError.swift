import Foundation

enum ProcessError: Error, Equatable, LocalizedError {
    case process(String)
    var errorDescription: String? {
        switch self { case .process(let message): return message }
    }
}
