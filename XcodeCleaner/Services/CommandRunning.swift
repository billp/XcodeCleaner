import Foundation

protocol CommandRunning: Sendable {
    func run(_ launchPath: String, _ args: [String]) async throws -> (status: Int32, stdout: Data, stderr: Data)
}

struct Shell: CommandRunning {
    func run(_ launchPath: String, _ args: [String]) async throws -> (status: Int32, stdout: Data, stderr: Data) {
        // Redirect child output to temp files rather than Pipes. A Pipe's OS buffer
        // is ~64KB; if the child writes more before anyone drains it (and we only
        // drain in terminationHandler, which runs *after* exit), the child blocks on
        // write and never exits → terminationHandler never fires → deadlock.
        // `/bin/ps -axo comm=` exceeds 64KB on a busy machine and hit exactly this.
        // Files have no such limit, so the child always runs to completion.
        let tmp = FileManager.default.temporaryDirectory
        let outURL = tmp.appendingPathComponent("xcc-\(UUID().uuidString).out")
        let errURL = tmp.appendingPathComponent("xcc-\(UUID().uuidString).err")
        FileManager.default.createFile(atPath: outURL.path, contents: nil)
        FileManager.default.createFile(atPath: errURL.path, contents: nil)
        let outHandle = try FileHandle(forWritingTo: outURL)
        let errHandle = try FileHandle(forWritingTo: errURL)

        return try await withCheckedThrowingContinuation { cont in
            let p = Process()
            p.executableURL = URL(fileURLWithPath: launchPath)
            p.arguments = args
            p.standardOutput = outHandle
            p.standardError = errHandle
            // terminationHandler captures only Sendable values (URLs + continuation);
            // it reads the files back after the process has exited and flushed.
            p.terminationHandler = { proc in
                let outData = (try? Data(contentsOf: outURL)) ?? Data()
                let errData = (try? Data(contentsOf: errURL)) ?? Data()
                try? FileManager.default.removeItem(at: outURL)
                try? FileManager.default.removeItem(at: errURL)
                cont.resume(returning: (proc.terminationStatus, outData, errData))
            }
            do {
                try p.run()
                // The child has its own dup'd descriptors; close our copies so they
                // don't leak (safe to do once the process has launched).
                try? outHandle.close()
                try? errHandle.close()
            } catch {
                try? outHandle.close()
                try? errHandle.close()
                try? FileManager.default.removeItem(at: outURL)
                try? FileManager.default.removeItem(at: errURL)
                cont.resume(throwing: error)
            }
        }
    }
}
