import Foundation

/// Helpers that keep tool file access confined to the project directory.
///
/// The app sandbox is intentionally disabled (see `CoreAIAssistant.entitlements`)
/// so the assistant can read/write project files and run shell commands. With
/// that freedom, a model (or prompt injection) must not be able to read
/// `~/.ssh`, `/etc/passwd`, or overwrite files outside the project. Every
/// path a tool resolves goes through `resolve(within:path:)` which rejects
/// anything that escapes `workingDirectory`.
enum PathSecurity {
    /// Resolves `path` (relative to `workingDirectory`) and returns the
    /// absolute, standardized URL only if it stays inside `workingDirectory`.
    /// Returns `nil` if the path escapes (e.g. via `../`, absolute paths,
    /// or `..namedfork` tricks).
    static func resolve(within workingDirectory: String, path: String) -> URL? {
        let base = (workingDirectory as NSString).standardizingPath
        // Treat `workingDirectory` as a directory so relative paths like
        // "Sources/foo" resolve *inside* it rather than next to it
        // (URL relativeTo strips the last component when the base has no
        // trailing slash).
        let baseURL = URL(fileURLWithPath: workingDirectory, isDirectory: true)
        let url = URL(fileURLWithPath: path, relativeTo: baseURL)
        let resolvedPath = (url.standardizedFileURL.path as NSString).standardizingPath
        guard resolvedPath == base || resolvedPath.hasPrefix(base + "/") else {
            return nil
        }
        return URL(fileURLWithPath: resolvedPath)
    }

    static let escapeError = "Error: path escapes the project directory and was rejected for safety."
}
