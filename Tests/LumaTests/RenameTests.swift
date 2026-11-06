import AppKit
import ReaderCore
import Testing
@testable import Luma

@MainActor struct RenameTests {
    let directory: URL
    let preferences: UserDefaults
    let domain = "local.luma.rename-tests.\(UUID().uuidString)"
    init() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        preferences = try #require(UserDefaults(suiteName: domain))
    }
    private func clean() {
        try? FileManager.default.removeItem(at: directory)
        preferences.removePersistentDomain(forName: domain)
    }
    private func open(_ url: URL, in workspace: Workspace) async throws -> DocumentTab {
        workspace.open([url]); let tab = try #require(workspace.activeTab)
        await tab.loadTask?.value
        return tab
    }
    private func wait(_ workspace: Workspace) async throws {
        let deadline = ContinuousClock.now + .seconds(5)
        while (!workspace.loadingDirectories.isEmpty || workspace.searching) && ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(10)) }
        try #require(workspace.loadingDirectories.isEmpty && !workspace.searching)
    }

    @Test func fileRenameKeepsTabDraftUndoAndSavesOnlyToNewPath() async throws {
        defer { clean() }
        _ = NSApplication.shared
        let file = directory.appendingPathComponent("note.md")
        try "original".write(to: file, atomically: true, encoding: .utf8)
        let workspace = Workspace(preferences: preferences); workspace.roots = [directory]
        let tab = try await open(file, in: workspace)
        let editor = tab.sourceEditor()
        editor.textView.insertText("draft ", replacementRange: NSRange(location: 0, length: 0))
        editor.textView.breakUndoCoalescing()
        let oldID = tab.id
        let renamed = try await workspace.rename(FileEntry(url: file, isDirectory: false), to: "新笔记.md")
        try await wait(workspace)
        #expect(workspace.activeTab === tab && workspace.activeID == tab.id && tab.id != oldID)
        #expect(tab.title == "新笔记.md" && tab.draft == "draft original" && tab.isDirty)
        #expect(tab.sourceEditor() === editor && tab.canUndo)
        workspace.undo(); #expect(tab.draft == "original")
        workspace.redo(); #expect(tab.draft == "draft original")
        workspace.open([renamed]); #expect(workspace.tabs.count == 1)
        #expect(await workspace.save(tab))
        #expect(try String(contentsOf: renamed, encoding: .utf8) == "draft original")
        #expect(!FileManager.default.fileExists(atPath: file.path))
        #expect(workspace.directories[directory]?.contains { $0.name == "新笔记.md" } == true)
        #expect(preferences.stringArray(forKey: "openFileTabs") == [tab.url.path])
    }

    @Test func folderRenameMovesRootsCachesOpenDescendantsAndPreservesSibling() async throws {
        defer { clean() }
        let folder = directory.appendingPathComponent("old", isDirectory: true)
        let child = folder.appendingPathComponent("child", isDirectory: true)
        let sibling = directory.appendingPathComponent("old-other", isDirectory: true)
        for url in [child, sibling] { try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true) }
        let first = child.appendingPathComponent("one.md"), second = folder.appendingPathComponent("two.txt"), other = sibling.appendingPathComponent("stay.txt")
        for file in [first, second, other] { try "original".write(to: file, atomically: true, encoding: .utf8) }
        let workspace = Workspace(preferences: preferences)
        workspace.roots = [directory, folder, child, sibling]; workspace.recent = [folder]
        workspace.expanded = [directory, folder, child]
        let one = try await open(first, in: workspace), two = try await open(second, in: workspace), untouched = try await open(other, in: workspace)
        one.edit("first draft"); two.edit("second draft")
        workspace.activeID = one.id
        workspace.loadDirectory(folder); workspace.loadDirectory(child)
        try await wait(workspace)
        // A deleted destination may still have cached data; moving into it must not duplicate keys.
        let stale = directory.appendingPathComponent("renamed", isDirectory: true)
        workspace.directories[stale] = []
        _ = try await workspace.rename(FileEntry(url: folder, isDirectory: true), to: "renamed")
        try await wait(workspace)
        #expect(workspace.activeTab === one && one.title == "one.md" && two.title == "two.txt")
        #expect(one.url.path.contains("/renamed/child/") && two.url.path.contains("/renamed/"))
        #expect(one.draft == "first draft" && two.draft == "second draft" && one.isDirty && two.isDirty)
        #expect(untouched.url.path == other.resolvingSymlinksInPath().path)
        #expect(workspace.roots.map(\.lastPathComponent) == [directory.lastPathComponent, "renamed", "child", "old-other"])
        #expect(workspace.expanded.contains { $0.lastPathComponent == "renamed" })
        #expect(!workspace.directories.keys.contains { $0.lastPathComponent == "old" })
        #expect(workspace.recent.first?.lastPathComponent == "renamed")
        #expect(await workspace.save(one))
        #expect(await workspace.save(two))
        #expect(try String(contentsOf: one.url, encoding: .utf8) == "first draft")
    }

    @Test func readingSessionAndBookmarksFollowRenameIncludingLaterCaptures() async throws {
        defer { clean() }
        let file = directory.appendingPathComponent("note.md")
        try "# Chapter".write(to: file, atomically: true, encoding: .utf8)
        let workspace = Workspace(preferences: preferences)
        let tab = try await open(file, in: workspace)
        let session = try #require(tab.readingSession)
        let location = MarkdownReadingLocation(offset: 432, progress: 0.4, blockKey: "chapter/p", blockProgress: 0.3, headingID: "chapter", headingProgress: 0.2)
        _ = session.addBookmark(at: location, title: "Chapter")
        tab.captureMarkdownPosition = { [weak tab] in tab?.rememberReadingPosition(location) }
        let oldKey = MarkdownReadingHistory.storageKey(for: tab.url)
        _ = try await workspace.rename(FileEntry(url: file, isDirectory: false), to: "renamed.md")
        #expect(tab.readingSession === session && tab.markdownLocation == location)
        let later = MarkdownReadingLocation(offset: 800, progress: 0.8, blockKey: "later", blockProgress: 0, headingID: "later", headingProgress: 0)
        session.remember(later)
        workspace.readingHistory.flush()
        #expect(preferences.data(forKey: oldKey) == nil)
        let fresh = MarkdownReadingHistory(preferences: preferences).session(for: tab.url)
        #expect(fresh.location == later && fresh.bookmarks.first?.title == "Chapter")
        let restarted = Workspace(preferences: preferences); restarted.restore()
        #expect(restarted.activeTab?.url == tab.url)
        for tab in restarted.tabs { await tab.loadTask?.value }
    }

    @Test func extensionChangesKeepDraftEditableAndReparseNewTextFormat() async throws {
        defer { clean() }
        let file = directory.appendingPathComponent("note.txt")
        try "original".write(to: file, atomically: true, encoding: .utf8)
        let workspace = Workspace(preferences: preferences)
        let tab = try await open(file, in: workspace)
        tab.edit(#"{"value":2}"#)
        _ = try await workspace.rename(FileEntry(url: tab.url, isDirectory: false), to: "note.json")
        await tab.previewTask?.value
        #expect(tab.kind == .json && tab.draft == #"{"value":2}"# && tab.isDirty)
        guard case .ready(.json) = tab.state else { Issue.record("Expected JSON preview"); return }
        _ = try await workspace.rename(FileEntry(url: tab.url, isDirectory: false), to: "note.bin")
        #expect(tab.canEdit && tab.showSource && tab.isDirty)
        #expect(await workspace.save(tab))
        #expect(try String(contentsOf: tab.url, encoding: .utf8) == #"{"value":2}"#)
    }

    @Test func failedOrBusyRenameLeavesNamesAndDraftIntact() async throws {
        defer { clean() }
        let file = directory.appendingPathComponent("note.txt")
        try "original".write(to: file, atomically: true, encoding: .utf8)
        let workspace = Workspace(preferences: preferences)
        let tab = try await open(file, in: workspace); tab.edit("draft")
        workspace.renameItem = { _, _ in throw CocoaError(.fileWriteNoPermission) }
        do { _ = try await workspace.rename(FileEntry(url: file, isDirectory: false), to: "other.txt"); Issue.record("Expected failure") }
        catch { }
        #expect(tab.title == "note.txt" && tab.draft == "draft" && !tab.isRenaming && !workspace.isRenaming)
        tab.isSaving = true
        do { _ = try await workspace.rename(FileEntry(url: file, isDirectory: false), to: "busy.txt"); Issue.record("Expected busy rejection") }
        catch { #expect(error is WorkspaceRenameError) }
        tab.isSaving = false
        #expect(try String(contentsOf: file, encoding: .utf8) == "original")
    }

    @Test func renameDuringTypingKeepsNewestDraftAndBlocksWritesToOldPath() async throws {
        defer { clean() }
        let file = directory.appendingPathComponent("note.txt")
        try "original".write(to: file, atomically: true, encoding: .utf8)
        let workspace = Workspace(preferences: preferences)
        let tab = try await open(file, in: workspace)
        workspace.renameItem = { url, name in
            #expect(tab.isRenaming)
            tab.edit("newest draft")
            #expect(await workspace.save(tab) == false)
            workspace.close(tab.id)
            #expect(workspace.tabs.count == 1)
            return try FileRenamer.rename(url, to: name)
        }
        _ = try await workspace.rename(FileEntry(url: file, isDirectory: false), to: "new.txt")
        #expect(tab.draft == "newest draft" && tab.isDirty)
        #expect(await workspace.save(tab))
        #expect(!FileManager.default.fileExists(atPath: file.path))
    }
    @Test func folderRenameWithoutTabsFinishesBeforeQuitIsAllowed() async throws {
        defer { clean() }
        let folder = directory.appendingPathComponent("old", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        let workspace = Workspace(preferences: preferences)
        workspace.roots = [folder]
        workspace.renameItem = { url, name in
            #expect(workspace.tabs.isEmpty)
            #expect(await workspace.confirmCloseAll() == false)
            return try FileRenamer.rename(url, to: name)
        }
        _ = try await workspace.rename(FileEntry(url: folder, isDirectory: true), to: "new")
        #expect(await workspace.confirmCloseAll())
        #expect(workspace.roots.first?.lastPathComponent == "new")
    }

}
