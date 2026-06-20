import Foundation

enum ScanError: Error, Equatable { case process(String) }

protocol CommandRunning: Sendable {
    func run(_ launchPath: String, _ args: [String]) async throws -> (status: Int32, stdout: Data, stderr: Data)
}

struct Shell: CommandRunning {
    func run(_ launchPath: String, _ args: [String]) async throws -> (status: Int32, stdout: Data, stderr: Data) {
        try await withCheckedThrowingContinuation { cont in
            let p = Process()
            p.executableURL = URL(fileURLWithPath: launchPath)
            p.arguments = args
            let out = Pipe()
            let err = Pipe()
            p.standardOutput = out
            p.standardError = err
            p.terminationHandler = { proc in
                let outData = (try? out.fileHandleForReading.readToEnd()) ?? Data()
                let errData = (try? err.fileHandleForReading.readToEnd()) ?? Data()
                cont.resume(returning: (proc.terminationStatus, outData, errData))
            }
            do { try p.run() } catch { cont.resume(throwing: error) }
        }
    }
}
