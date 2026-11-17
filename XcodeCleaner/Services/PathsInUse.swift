import Foundation

/// Decides which cleanable entries a running build still needs, so a clean can
/// go ahead mid-build and leave those alone.
///
/// The paths come from `BuildDetecting.pathsInUse()`: the folders on each
/// build's command line plus the files its processes have open.
enum PathsInUse {
    /// Canonical form for comparing paths: standardized, symlinks resolved
    /// (`/tmp` vs `/private/tmp`), no trailing slash.
    static func normalize(_ path: String) -> String {
        URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath().path
    }

    /// Whether deleting `entry` would pull files out from under a build:
    /// - a path in use is `entry` itself or lies inside it;
    /// - `entry` is a DerivedData folder whose project is being built (its
    ///   `info.plist` names the workspace, which is on the build's command line);
    /// - `entry` is a shared cache (`ModuleCache.noindex`, `SymbolCache.noindex`…)
    ///   sitting next to a folder that's in use — every build in that DerivedData
    ///   reads and writes it.
    ///
    /// `entry` and `paths` must already be normalized.
    static func isInUse(_ entry: String, paths: Set<String>) -> Bool {
        guard !paths.isEmpty else { return false }
        if contains(entry, anyOf: paths) { return true }
        if let workspace = derivedDataWorkspace(of: entry), paths.contains(normalize(workspace)) { return true }
        if entry.hasSuffix(".noindex") {
            let parent = (entry as NSString).deletingLastPathComponent
            return contains(parent, anyOf: paths)
        }
        return false
    }

    private static func contains(_ directory: String, anyOf paths: Set<String>) -> Bool {
        let prefix = directory.hasSuffix("/") ? directory : directory + "/"
        return paths.contains { $0 == directory || $0.hasPrefix(prefix) }
    }

    /// `WorkspacePath` from a DerivedData folder's `info.plist`, if it has one.
    private static func derivedDataWorkspace(of entry: String) -> String? {
        let plist = (entry as NSString).appendingPathComponent("info.plist")
        guard let data = FileManager.default.contents(atPath: plist),
              let dict = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        else { return nil }
        return dict["WorkspacePath"] as? String
    }
}
