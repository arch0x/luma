import AppKit
import ReaderCore
import Testing
@testable import Luma

@MainActor struct MoveTests {
    let base: URL
    let source: URL
    let target: URL
    let preferences: UserDefaults
    let domain = "local.luma.move-tests.\(UUID().uuidString)"
    init() throws {
        base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        source = base.appendingPathComponent("Source", isDirectory: true)
        target = base.appendingPathComponent("Target", isDirectory: true)
        for folder in [source, target] { try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true) }
        preferences = try #require(UserDefaults(suiteName: domain))
    }
    private func clean() {
        try? FileManager.default.removeItem(at: base)
        preferences.removePersistentDomain(forName: domain)
    }
    private func workspace() -> Workspace {
        let workspace = Workspace(preferences: preferences)
        workspace.roots = [source, target]
        return workspace
    }
    private func open(_ file: URL, in workspace: Workspace) async throws -> DocumentTab {
        workspace.open([file]); let tab = try #require(workspace.activeTab)
        await tab.loadTask?.value
        return tab
    }
    private func wait(_ workspace: Workspace) async throws {
        let deadline = ContinuousClock.now + .seconds(5)
        while (!workspace.loadingDirectories.isEmpty || workspace.searching) && ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(10)) }
        try #require(workspace.loadingDirectories.isEmpty && !workspace.searching)
    }
    private func payload(_ item: SidebarDragItem?) async throws -> SidebarDragItem { try #require(item) }

    @Test func movingDirtyTabPreservesUndoAndSavePath() async throws {
        defer { clean() }
        _ = NSApplication.shared
        let file = source.appendingPathComponent("笔记.md")
        try "original".write(to: file, atomically: true, encoding: .utf8)
        let workspace = workspace()
        let tab = try await open(file, in: workspace)
        let editor = tab.sourceEditor()
        editor.textView.insertText("draft ", replacementRange: NSRange(location: 0, length: 0))
        editor.textView.breakUndoCoalescing()
        let provider = workspace.beginSidebarDrag(for: FileEntry(url: file, isDirectory: false))
        let item = try await payload(provider)
        #expect(workspace.canMove(item, into: target))
        #expect(await workspace.receiveDrop(item, into: target))
        try await wait(workspace)
        #expect(workspace.activeTab === tab && tab.title == "笔记.md" && tab.url.deletingLastPathComponent().lastPathComponent == "Target")
        #expect(tab.isDirty && tab.draft == "draft original" && tab.sourceEditor() === editor)
        workspace.undo(); #expect(tab.draft == "original")
        workspace.redo(); #expect(tab.draft == "draft original")
        #expect(await workspace.save(tab))
        #expect(try String(contentsOf: tab.url, encoding: .utf8) == "draft original")
        #expect(!FileManager.default.fileExists(atPath: file.path))
        #expect(workspace.expanded.contains(target))
        #expect(workspace.directories[source]?.contains { $0.name == "笔记.md" } == false)
        #expect(workspace.directories[target]?.contains { $0.name == "笔记.md" } == true)
        #expect(await workspace.receiveDrop(item, into: target) == false)
    }

    @Test func folderMoveUpdatesOpenDescendantsRootsAndReadingHistory() async throws {
        defer { clean() }
        let folder = source.appendingPathComponent("Folder", isDirectory: true)
        let child = folder.appendingPathComponent("Child", isDirectory: true)
        try FileManager.default.createDirectory(at: child, withIntermediateDirectories: true)
        let file = child.appendingPathComponent("note.md")
        try "# Read".write(to: file, atomically: true, encoding: .utf8)
        let workspace = workspace()
        workspace.roots.append(folder)
        workspace.expanded = [source, folder, child]
        let tab = try await open(file, in: workspace)
        tab.edit("# Draft")
        let session = try #require(tab.readingSession)
        let location = MarkdownReadingLocation(offset: 400, progress: 0.3, blockKey: "read", blockProgress: 0.2, headingID: "read", headingProgress: 0.1)
        tab.rememberReadingPosition(location)
        _ = session.addBookmark(at: location, title: "Read")
        let moved = try await workspace.move(FileEntry(url: folder, isDirectory: true), into: target)
        try await wait(workspace)
        #expect(tab.url.path.contains("/Target/Folder/Child/") && workspace.activeTab === tab)
        #expect(tab.draft == "# Draft" && tab.isDirty && tab.readingSession === session)
        #expect(workspace.roots.contains { WorkspacePath.item($0) == WorkspacePath.item(moved) })
        #expect(workspace.expanded.contains { $0.path.contains("/Target/Folder/Child") })
        workspace.readingHistory.flush()
        #expect(MarkdownReadingHistory(preferences: preferences).session(for: tab.url).bookmarks.count == 1)
        #expect(await workspace.save(tab))
        #expect(!FileManager.default.fileExists(atPath: file.path))
        #expect(preferences.stringArray(forKey: "openFileTabs") == [tab.url.path])
    }

    @Test func hoverValidationRejectsParentSelfChildAndOtherWorkspace() throws {
        defer { clean() }
        let folder = source.appendingPathComponent("Folder", isDirectory: true)
        let child = folder.appendingPathComponent("Child", isDirectory: true)
        try FileManager.default.createDirectory(at: child, withIntermediateDirectories: true)
        let workspace = workspace()
        _ = workspace.beginSidebarDrag(for: FileEntry(url: folder, isDirectory: true))
        let item = try #require(workspace.draggedItem)
        #expect(!workspace.canMove(item, into: source))
        #expect(!workspace.canMove(item, into: folder))
        #expect(!workspace.canMove(item, into: child))
        #expect(!workspace.canMove(item, into: base))
        #expect(workspace.canMove(item, into: target))
        let other = Workspace(preferences: preferences)
        other.roots = [source, target]
        #expect(!other.canMove(item, into: target))
    }

    @Test func rejectedCollisionKeepsBothFilesAndDraft() async throws {
        defer { clean() }
        let file = source.appendingPathComponent("note.txt")
        let existing = target.appendingPathComponent("note.txt")
        try "source".write(to: file, atomically: true, encoding: .utf8)
        try "target".write(to: existing, atomically: true, encoding: .utf8)
        let workspace = workspace()
        let tab = try await open(file, in: workspace); tab.edit("draft")
        let item = try await payload(workspace.beginSidebarDrag(for: FileEntry(url: file, isDirectory: false)))
        #expect(await workspace.receiveDrop(item, into: target) == false)
        #expect(tab.draft == "draft" && tab.title == "note.txt" && tab.url.deletingLastPathComponent().lastPathComponent == "Source")
        #expect(try String(contentsOf: file, encoding: .utf8) == "source")
        #expect(try String(contentsOf: existing, encoding: .utf8) == "target")
        #expect(workspace.notice?.contains("已存在") == true)
    }

    @Test func failedMovePreservesDraftAndRejectsOutsideScope() async throws {
        defer { clean() }
        let file = source.appendingPathComponent("note.txt")
        try "original".write(to: file, atomically: true, encoding: .utf8)
        let workspace = workspace()
        let tab = try await open(file, in: workspace); tab.edit("draft")
        workspace.moveItem = { _, _ in throw CocoaError(.fileWriteNoPermission) }
        let item = try await payload(workspace.beginSidebarDrag(for: FileEntry(url: file, isDirectory: false)))
        #expect(await workspace.receiveDrop(item, into: target) == false)
        #expect(tab.draft == "draft" && tab.isDirty && !workspace.isRenaming && !tab.isRenaming)
        do { _ = try await workspace.move(FileEntry(url: file, isDirectory: false), into: base); Issue.record("Expected scope rejection") }
        catch { #expect(error is WorkspaceMoveError) }
        #expect(try String(contentsOf: file, encoding: .utf8) == "original")
    }

    @Test func staleDragPayloadCannotMovePreviousSource() async throws {
        defer { clean() }
        let first = source.appendingPathComponent("first.txt"), second = source.appendingPathComponent("second.txt")
        for file in [first, second] { try "keep".write(to: file, atomically: true, encoding: .utf8) }
        let workspace = workspace()
        let old = try await payload(workspace.beginSidebarDrag(for: FileEntry(url: first, isDirectory: false)))
        let current = try await payload(workspace.beginSidebarDrag(for: FileEntry(url: second, isDirectory: false)))
        #expect(await workspace.receiveDrop(old, into: target) == false)
        #expect(workspace.draggedItem == current)
        #expect(await workspace.receiveDrop(current, into: target))
        #expect(FileManager.default.fileExists(atPath: first.path))
    }

    @Test func moveBlocksQuitAndSavesUntilNewPathsAreCommitted() async throws {
        defer { clean() }
        let file = source.appendingPathComponent("note.txt")
        try "original".write(to: file, atomically: true, encoding: .utf8)
        let workspace = workspace()
        let tab = try await open(file, in: workspace)
        workspace.moveItem = { url, folder in
            #expect(await workspace.confirmCloseAll() == false)
            tab.edit("new draft during move")
            #expect(await workspace.save(tab) == false)
            return try FileMover.move(url, into: folder)
        }
        _ = try await workspace.move(FileEntry(url: file, isDirectory: false), into: target)
        #expect(tab.draft == "new draft during move" && tab.isDirty)
        #expect(await workspace.save(tab))
        #expect(!FileManager.default.fileExists(atPath: file.path))
    }
}
