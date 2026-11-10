import AppKit
import ReaderCore
import Testing
@testable import Luma

@MainActor struct FileActionTests {
    let base: URL
    let directory: URL
    let bin: URL
    let preferences: UserDefaults
    let domain = "local.luma.file-actions.\(UUID().uuidString)"
    init() throws {
        base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        directory = base.appendingPathComponent("Workspace", isDirectory: true)
        bin = base.appendingPathComponent("TestBin", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        preferences = try #require(UserDefaults(suiteName: domain))
    }
    private func clean() {
        try? FileManager.default.removeItem(at: base)
        preferences.removePersistentDomain(forName: domain)
    }
    private func workspace() -> Workspace {
        let workspace = chineseWorkspace(preferences: preferences)
        workspace.roots = [directory]
        let bin = bin
        workspace.recycleItem = { url in
            try FileManager.default.moveItem(at: url, to: bin.appendingPathComponent(url.lastPathComponent))
        }
        return workspace
    }
    private func open(_ file: URL, in workspace: Workspace) async throws -> DocumentTab {
        workspace.open([file])
        let tab = try #require(workspace.activeTab)
        await tab.loadTask?.value
        return tab
    }
    private func waitForDirectory(_ url: URL, in workspace: Workspace) async throws {
        let deadline = ContinuousClock.now + .seconds(5)
        while workspace.loadingDirectories.contains(url) && ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        try #require(!workspace.loadingDirectories.contains(url))
    }

    @Test func newFolderRefreshesItsParentWithoutChangingOpenDraft() async throws {
        defer { clean() }
        let file = directory.appendingPathComponent("note.txt")
        try "original".write(to: file, atomically: true, encoding: .utf8)
        let workspace = workspace()
        let tab = try await open(file, in: workspace)
        tab.edit("draft")
        workspace.loadDirectory(directory)
        try await waitForDirectory(directory, in: workspace)
        let created = try await workspace.createFolder(named: "项目 资料", in: directory)
        try await waitForDirectory(directory, in: workspace)
        #expect(try created.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true)
        #expect(workspace.directories[directory]?.contains { $0.isDirectory && $0.name == "项目 资料" } == true)
        #expect(workspace.expanded.contains(directory))
        #expect(workspace.activeTab === tab && tab.draft == "draft" && tab.isDirty)
        #expect(workspace.tabs.count == 1)
    }

    @Test(arguments: [false, true])
    func trashClosesOnlyAffectedTabsAndRefreshesParent(folder: Bool) async throws {
        defer { clean() }
        let target = directory.appendingPathComponent(folder ? "target" : "target.txt")
        if folder { try FileManager.default.createDirectory(at: target, withIntermediateDirectories: false) }
        let file = folder ? target.appendingPathComponent("inside.txt") : target
        let sibling = directory.appendingPathComponent("target-other.txt")
        try "inside".write(to: file, atomically: true, encoding: .utf8)
        try "outside".write(to: sibling, atomically: true, encoding: .utf8)
        let workspace = workspace()
        _ = try await open(file, in: workspace)
        let other = try await open(sibling, in: workspace)
        other.edit("unrelated draft")
        workspace.loadDirectory(directory)
        try await waitForDirectory(directory, in: workspace)
        #expect(await workspace.trash(FileEntry(url: target, isDirectory: folder)))
        try await waitForDirectory(directory, in: workspace)
        #expect(!FileManager.default.fileExists(atPath: target.path))
        #expect(FileManager.default.fileExists(atPath: bin.appendingPathComponent(target.lastPathComponent).path))
        #expect(workspace.tabs.count == 1 && workspace.activeTab === other)
        #expect(other.draft == "unrelated draft" && other.isDirty)
        #expect(workspace.directories[directory]?.contains { $0.name == target.lastPathComponent } == false)
    }

    @Test(arguments: [UnsavedChoice.save, .discard, .cancel])
    func trashHonorsUnsavedChoice(choice: UnsavedChoice) async throws {
        defer { clean() }
        let file = directory.appendingPathComponent("note.txt")
        try "original".write(to: file, atomically: true, encoding: .utf8)
        let workspace = workspace()
        let tab = try await open(file, in: workspace)
        tab.edit("draft")
        workspace.chooseUnsaved = { _ in choice }
        let success = await workspace.trash(FileEntry(url: file, isDirectory: false))
        if choice == .cancel {
            #expect(!success && tab.isDirty && workspace.tabs.count == 1)
            #expect(try String(contentsOf: file, encoding: .utf8) == "original")
        } else {
            #expect(success && workspace.tabs.isEmpty)
            #expect(try String(contentsOf: bin.appendingPathComponent("note.txt"), encoding: .utf8) == (choice == .save ? "draft" : "original"))
        }
    }

    @Test func failedTrashKeepsDiscardedDraftAndOriginalFile() async throws {
        defer { clean() }
        let file = directory.appendingPathComponent("note.txt")
        try "original".write(to: file, atomically: true, encoding: .utf8)
        let workspace = workspace()
        let tab = try await open(file, in: workspace)
        tab.edit("draft")
        workspace.chooseUnsaved = { _ in .discard }
        workspace.recycleItem = { _ in throw CocoaError(.fileWriteNoPermission) }
        #expect(await workspace.trash(FileEntry(url: file, isDirectory: false)) == false)
        #expect(workspace.activeTab === tab && tab.draft == "draft" && tab.isDirty)
        #expect(try String(contentsOf: file, encoding: .utf8) == "original")
        #expect(workspace.notice?.contains("无法") == true)
    }

    @Test func cancelledFolderTrashDoesNotDiscardEarlierReviewedDrafts() async throws {
        defer { clean() }
        let first = directory.appendingPathComponent("one.txt")
        let second = directory.appendingPathComponent("two.txt")
        try "original one".write(to: first, atomically: true, encoding: .utf8)
        try "original two".write(to: second, atomically: true, encoding: .utf8)
        let workspace = workspace()
        let one = try await open(first, in: workspace)
        let two = try await open(second, in: workspace)
        one.edit("draft one"); two.edit("draft two")
        workspace.chooseUnsaved = { $0 === one ? .discard : .cancel }
        #expect(await workspace.trash(FileEntry(url: directory, isDirectory: true)) == false)
        #expect(one.draft == "draft one" && two.draft == "draft two" && one.isDirty && two.isDirty)
        #expect(FileManager.default.fileExists(atPath: directory.path))
    }

    @Test func editsAfterReviewCancelTrashBeforeAnyMove() async throws {
        defer { clean() }
        let first = directory.appendingPathComponent("one.txt")
        let second = directory.appendingPathComponent("two.txt")
        try "one".write(to: first, atomically: true, encoding: .utf8)
        try "two".write(to: second, atomically: true, encoding: .utf8)
        let workspace = workspace()
        let one = try await open(first, in: workspace)
        let two = try await open(second, in: workspace)
        one.edit("draft one"); two.edit("draft two")
        workspace.chooseUnsaved = { tab in
            if tab === two { one.edit("new edit after first review") }
            return .discard
        }
        #expect(await workspace.trash(FileEntry(url: directory, isDirectory: true)) == false)
        #expect(one.draft == "new edit after first review" && one.isDirty && two.isDirty)
        #expect(FileManager.default.fileExists(atPath: first.path))
    }

    @Test func editsDuringMoveStayOpenAndMarkedAsExternalChange() async throws {
        defer { clean() }
        let file = directory.appendingPathComponent("note.txt")
        try "original".write(to: file, atomically: true, encoding: .utf8)
        let workspace = workspace()
        let tab = try await open(file, in: workspace)
        tab.edit("reviewed draft")
        workspace.chooseUnsaved = { _ in .discard }
        let destination = bin.appendingPathComponent("note.txt")
        workspace.recycleItem = { url in
            tab.edit("new draft during move")
            try FileManager.default.moveItem(at: url, to: destination)
        }
        #expect(await workspace.trash(FileEntry(url: file, isDirectory: false)))
        #expect(workspace.activeTab === tab && tab.isDirty && tab.externalChange)
        #expect(tab.draft == "new draft during move")
    }

    @Test func trashingRootRemovesNestedRootsAndKeepsSiblingRoot() async throws {
        defer { clean() }
        let nested = directory.appendingPathComponent("nested", isDirectory: true)
        let sibling = base.appendingPathComponent("Workspace-other", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: sibling, withIntermediateDirectories: true)
        let workspace = workspace()
        workspace.roots = [directory, nested, sibling]
        workspace.expanded = Set(workspace.roots)
        #expect(await workspace.trash(FileEntry(url: directory, isDirectory: true)))
        #expect(workspace.roots == [sibling])
        #expect(workspace.expanded == [sibling])
        #expect(FileManager.default.fileExists(atPath: sibling.path))
        #expect(preferences.stringArray(forKey: "workspaceFolders") == [sibling.path])
    }

    @Test func trashingSymlinkDoesNotTouchTargetOrItsDraft() async throws {
        defer { clean() }
        let target = base.appendingPathComponent("outside.txt")
        let link = directory.appendingPathComponent("link.txt")
        try "outside".write(to: target, atomically: true, encoding: .utf8)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
        let workspace = workspace()
        let tab = try await open(target, in: workspace)
        tab.edit("outside draft")
        workspace.chooseUnsaved = { _ in Issue.record("Unrelated target must not be reviewed"); return .cancel }
        #expect(await workspace.trash(FileEntry(url: link, isDirectory: false)))
        #expect(workspace.activeTab === tab && tab.draft == "outside draft" && tab.isDirty)
        #expect(try String(contentsOf: target, encoding: .utf8) == "outside")
        #expect(try bin.appendingPathComponent("link.txt").resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink == true)
    }

    @Test func nativeTrashMovesOnlyOwnedFixtureAndCanRestoreIt() async throws {
        defer { clean() }
        let file = directory.appendingPathComponent("Luma-test-\(UUID().uuidString).txt")
        try "fixture".write(to: file, atomically: true, encoding: .utf8)
        let destination = try #require(try await FileService().moveToTrash(at: file))
        defer { try? FileManager.default.moveItem(at: destination, to: file) }
        #expect(!FileManager.default.fileExists(atPath: file.path))
        #expect(try String(contentsOf: destination, encoding: .utf8) == "fixture")
    }
}
