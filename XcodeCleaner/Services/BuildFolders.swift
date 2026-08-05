import Foundation

/// Locates SwiftPM `.build` directories beneath a root.
///
/// Uses `find` with `-prune` so a matched `.build` is never descended into —
/// nested matches can't inflate the count and the delete never races itself.
/// `find` exits non-zero when it can't read a subdirectory (routine while
/// walking a home folder full of protected caches), but the paths it already
/// emitted on stdout are still valid, so its exit status is ignored and only
/// stdout is parsed. Paths are NUL-delimited (`-print0`) to survive spaces.
///
/// The `<root>/Library` subtree is pruned up front: SwiftPM never puts a
/// `.build` there, and walking into `~/Library/Containers` (other apps'
/// sandboxed data) triggers macOS's "access data from other apps" privacy
/// prompt. Skipping it avoids the prompt and speeds up the scan.
enum BuildFolders {
    static func paths(root: String, runner: CommandRunning) async throws -> [String] {
        guard FileManager.default.fileExists(atPath: root) else { return [] }
        let (_, data, _) = try await runner.run(
            "/usr/bin/find",
            [
                root,
                "-path", "\(root)/Library", "-prune",
                "-o",
                "-type", "d", "-name", ".build", "-prune", "-print0"
            ]
        )
        let text = String(data: data, encoding: .utf8) ?? ""
        return text.split(separator: "\0").map(String.init).filter { !$0.isEmpty }
    }
}
