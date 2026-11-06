import Foundation

nonisolated enum WorkspacePath {
    static func normalized(_ url: URL) -> String { url.resolvingSymlinksInPath().standardizedFileURL.path }
    static func contains(_ parent: String, _ child: String) -> Bool {
        child == parent || child.hasPrefix(parent == "/" ? "/" : parent + "/")
    }
    // Resolve parent aliases without following a final symbolic link that is being trashed.
    static func item(_ url: URL) -> String {
        url.deletingLastPathComponent().resolvingSymlinksInPath().appendingPathComponent(url.lastPathComponent).path
    }
}

