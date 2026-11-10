import Foundation
import Testing
import ReaderCore
@testable import Luma

@MainActor struct WorkspaceExpansionTests {
    let directory: URL
    let preferences: UserDefaults
    let domain = "local.luma.expansion-tests.\(UUID())"

    init() throws {
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
        directory = temporary.resolvingSymlinksInPath().standardizedFileURL
        preferences = try #require(UserDefaults(suiteName: domain))
    }
    private func clean() {
        preferences.removePersistentDomain(forName: domain)
        try? FileManager.default.removeItem(at: directory)
    }
    private func folder(_ path: String) throws -> URL {
        let url = directory.appendingPathComponent(path, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
    private func paths(_ urls: Set<URL>) -> Set<String> { Set(urls.map(WorkspacePath.normalized)) }
    private func relaunched() -> Workspace {
        let workspace = Workspace(preferences: preferences)
        workspace.restore()
        return workspace
    }
    private func waitForTree(_ workspace: Workspace) async throws {
        let deadline = ContinuousClock.now + .seconds(5)
        while !workspace.loadingDirectories.isEmpty && ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(10)) }
        try #require(workspace.loadingDirectories.isEmpty)
        for tab in workspace.tabs { await tab.loadTask?.value }
    }

    @Test func relaunchRestoresOnlyExpandedProjectAndItsNestedFolders() async throws {
        defer { clean() }
        let first = try folder("First"), second = try folder("Second")
        let source = try folder("First/Sources"), nested = try folder("First/Sources/Readers")
        let file = second.appendingPathComponent("note.txt")
        try "Read without expanding this project".write(to: file, atomically: true, encoding: .utf8)
        let workspace = Workspace(preferences: preferences)
        workspace.addFolder(first); workspace.addFolder(second)
        workspace.toggleDirectory(second)
        workspace.toggleDirectory(source); workspace.toggleDirectory(nested)
        workspace.open([file])
        try await waitForTree(workspace)

        let restored = relaunched()
        try await waitForTree(restored)
        #expect(restored.roots == workspace.roots)
        #expect(paths(restored.expanded) == paths([first, source, nested]))
        #expect(!restored.expanded.contains(second), "Restoring its active file must not unfold a collapsed project")
        #expect(restored.activeTab?.url == file)
        #expect(restored.directories[source]?.contains { $0.url.lastPathComponent == "Readers" } == true)
        #expect(restored.directories[nested] != nil, "An expanded nested folder must have loaded contents instead of an endless spinner")
    }

    @Test func collapsingEverythingSurvivesRepeatedRelaunchAndRefresh() async throws {
        defer { clean() }
        let first = try folder("First"), second = try folder("Second")
        let workspace = Workspace(preferences: preferences)
        workspace.addFolder(first); workspace.addFolder(second)
        workspace.toggleDirectory(first); workspace.toggleDirectory(second)
        try await waitForTree(workspace)
        let restored = relaunched()
        restored.refreshDirectories()
        try await waitForTree(restored)
        #expect(restored.roots.count == 2 && restored.expanded.isEmpty)
        let again = relaunched()
        try await waitForTree(again)
        #expect(again.expanded.isEmpty)
        again.addFolder(try folder("New project"))
        #expect(again.expanded.count == 1, "An explicitly added project should still open immediately")
        try await waitForTree(again)
    }

    @Test func collapsedParentDoesNotLoseItsRememberedChildrenOrOpenOnLaunch() async throws {
        defer { clean() }
        let root = try folder("Project"), child = try folder("Project/Child")
        let workspace = Workspace(preferences: preferences)
        workspace.addFolder(root); workspace.toggleDirectory(child); workspace.toggleDirectory(root)
        try await waitForTree(workspace)
        let restored = relaunched()
        try await waitForTree(restored)
        #expect(!restored.expanded.contains(root) && restored.expanded.contains(child))
        restored.toggleDirectory(root)
        #expect(restored.expanded.contains(child) && restored.directories[child] != nil)
        restored.restore()
        #expect(restored.expanded.contains(root), "Repeated view appearance must not reset a user's current choice")
    }

    @Test func legacyPreferencesStartCollapsedUntilUserMakesAChoice() async throws {
        defer { clean() }
        let first = try folder("First"), second = try folder("Second")
        let file = directory.appendingPathComponent("not-a-folder.txt")
        try "text".write(to: file, atomically: true, encoding: .utf8)
        preferences.set([first.path, second.path, file.path], forKey: "workspaceFolders")
        let restored = relaunched()
        try await waitForTree(restored)
        #expect(restored.roots.count == 2 && restored.expanded.isEmpty)
        restored.toggleDirectory(second)
        let again = relaunched()
        try await waitForTree(again)
        #expect(paths(again.expanded) == paths([second]))
    }

    @Test func staleOrOutOfWorkspaceEntriesAreNotRestoredOrScanned() async throws {
        defer { clean() }
        let root = try folder("Project"), child = try folder("Project/Child"), outside = try folder("Project-other")
        let file = root.appendingPathComponent("file.txt")
        try "text".write(to: file, atomically: true, encoding: .utf8)
        let link = root.appendingPathComponent("link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: outside)
        preferences.set([root.path], forKey: "workspaceFolders")
        preferences.set([root.path, child.path, root.appendingPathComponent("missing").path, file.path, outside.path, link.path, "relative"], forKey: "expandedWorkspaceDirectories")
        let restored = relaunched()
        try await waitForTree(restored)
        #expect(paths(restored.expanded) == paths([root, child]))
        #expect(restored.directories[outside] == nil && restored.directories[link] == nil)
    }

    @Test func renamingAndRemovingProjectsUpdatesTheNextLaunch() async throws {
        defer { clean() }
        let first = try folder("First"), second = try folder("Second"), child = try folder("First/Child")
        let workspace = Workspace(preferences: preferences)
        workspace.addFolder(first); workspace.addFolder(second)
        workspace.toggleDirectory(second); workspace.toggleDirectory(child)
        try await waitForTree(workspace)
        let renamed = try await workspace.rename(FileEntry(url: first, isDirectory: true), to: "Renamed")
        try await waitForTree(workspace)
        let restored = relaunched()
        try await waitForTree(restored)
        #expect(paths(restored.expanded) == paths([renamed, renamed.appendingPathComponent("Child", isDirectory: true)]))
        restored.removeFolder(renamed)
        let again = relaunched()
        try await waitForTree(again)
        #expect(paths(Set(again.roots)) == paths([second]) && again.expanded.isEmpty)
        again.addFolder(renamed)
        #expect(paths(again.expanded) == paths([renamed]), "Removing a project must discard its old nested expansion flags")
        try await waitForTree(again)
    }
}
