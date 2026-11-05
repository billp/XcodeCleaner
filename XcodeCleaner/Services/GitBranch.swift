import Foundation

/// Reads the checked-out branch straight from git metadata (no `git` process),
/// so it's cheap enough to run on every build poll.
enum GitBranch {
    /// The branch of the repository or worktree containing `path` (a file or
    /// directory). A detached HEAD yields its short commit hash.
    static func name(containing path: String, fileManager: FileManager = .default) -> String? {
        var directory = URL(fileURLWithPath: path).standardizedFileURL
        while true {
            let dotGit = directory.appendingPathComponent(".git")
            var isDirectory: ObjCBool = false
            if fileManager.fileExists(atPath: dotGit.path, isDirectory: &isDirectory) {
                guard let gitDir = isDirectory.boolValue ? dotGit : linkedGitDir(dotGit, from: directory),
                      let head = try? String(contentsOf: gitDir.appendingPathComponent("HEAD"), encoding: .utf8)
                else { return nil }
                return parseHead(head)
            }
            let parent = directory.deletingLastPathComponent()
            if parent.path == directory.path { return nil }
            directory = parent
        }
    }

    /// A worktree's `.git` is a file: "gitdir: /repo/.git/worktrees/<name>".
    private static func linkedGitDir(_ file: URL, from directory: URL) -> URL? {
        guard let text = try? String(contentsOf: file, encoding: .utf8),
              let line = text.split(separator: "\n").first, line.hasPrefix("gitdir:")
        else { return nil }
        let path = line.dropFirst("gitdir:".count).trimmingCharacters(in: .whitespaces)
        return URL(fileURLWithPath: path, relativeTo: directory).standardizedFileURL
    }

    /// "ref: refs/heads/feature/x" → "feature/x"; a bare hash → its first 7 chars.
    static func parseHead(_ text: String) -> String? {
        let head = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if head.hasPrefix("ref: refs/heads/") { return String(head.dropFirst("ref: refs/heads/".count)) }
        if head.hasPrefix("ref: ") { return String(head.dropFirst("ref: ".count)) }
        return head.isEmpty ? nil : String(head.prefix(7))
    }

    /// Fallback label outside git: the folder holding a workspace/project, or the
    /// directory itself.
    static func folderName(of path: String) -> String? {
        let ext = (path as NSString).pathExtension
        let folder = ["xcworkspace", "xcodeproj"].contains(ext) ? (path as NSString).deletingLastPathComponent : path
        let name = (folder as NSString).lastPathComponent
        return name.isEmpty || name == "/" ? nil : name
    }
}
