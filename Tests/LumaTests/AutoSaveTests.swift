import AppKit
import Testing
import ReaderCore
@testable import Luma

@MainActor @Suite(.serialized) struct AutoSaveTests {
    let directory: URL
    let preferences: UserDefaults
    let domain = "local.luma.autosave-tests.\(UUID().uuidString)"

    init() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        preferences = try #require(UserDefaults(suiteName: domain))
    }
    private func clean(_ workspace: Workspace) {
        workspace.autoSaveEnabled = false
        try? FileManager.default.removeItem(at: directory)
        preferences.removePersistentDomain(forName: domain)
    }
    private func open(_ text: String = "original", name: String = "note.md", in workspace: Workspace) async throws -> DocumentTab {
        let file = directory.appendingPathComponent(name)
        try text.write(to: file, atomically: true, encoding: .utf8)
        workspace.open([file])
        let tab = try #require(workspace.activeTab)
        await tab.loadTask?.value
        return tab
    }
    private func finishAutoSave(_ tab: DocumentTab) async throws {
        let deadline = ContinuousClock.now + .seconds(3)
        try #require(tab.autoSaveTask != nil)
        while let task = tab.autoSaveTask, ContinuousClock.now < deadline { await task.value }
        try #require(tab.autoSaveTask == nil, "Autosave did not finish")
    }

    @Test func disabledByDefaultAndPreferenceSurvivesWorkspaceRecreation() async throws {
        let workspace = Workspace(preferences: preferences, autoSaveDelay: .milliseconds(30))
        defer { clean(workspace) }
        #expect(!workspace.autoSaveEnabled)
        let tab = try await open(in: workspace)
        tab.edit("manual draft")
        #expect(tab.autoSaveTask == nil)
        try await Task.sleep(for: .milliseconds(80))
        #expect(try String(contentsOf: tab.url, encoding: .utf8) == "original")
        #expect(tab.isDirty)
        workspace.autoSaveEnabled = true
        #expect(Workspace(preferences: preferences).autoSaveEnabled)
        workspace.autoSaveEnabled = false
        #expect(!Workspace(preferences: preferences).autoSaveEnabled)
    }

    @Test func disablingCancelsPendingSaveAndEnablingSavesExistingDraft() async throws {
        let workspace = Workspace(preferences: preferences, autoSaveDelay: .milliseconds(40))
        defer { clean(workspace) }
        let tab = try await open(in: workspace)
        tab.edit("pending draft")
        workspace.autoSaveEnabled = true
        let pending = try #require(tab.autoSaveTask)
        workspace.autoSaveEnabled = false
        await pending.value
        #expect(pending.isCancelled && tab.autoSaveTask == nil)
        #expect(try String(contentsOf: tab.url, encoding: .utf8) == "original")
        workspace.autoSaveEnabled = true
        try await finishAutoSave(tab)
        #expect(try String(contentsOf: tab.url, encoding: .utf8) == "pending draft")
        #expect(!tab.isDirty)
    }

    @Test(arguments: ["md", "txt", "swift", "json", "csv", "tsv"])
    func savesLatestDraftAndPreservesBackgroundTabs(ext: String) async throws {
        let workspace = Workspace(preferences: preferences, autoSaveDelay: .milliseconds(30))
        defer { clean(workspace) }
        workspace.autoSaveEnabled = true
        let before = ext == "json" ? "{\"n\":1}" : "name,count\noriginal,1"
        let after = ext == "json" ? "{\"n\":2}" : "name,count\nlatest,2"
        let first = try await open(before, name: "first.\(ext)", in: workspace)
        let second = try await open("second", name: "second.txt", in: workspace)
        first.edit("obsolete")
        let obsolete = try #require(first.autoSaveTask)
        first.edit(after)
        second.edit("background-safe")
        #expect(obsolete.isCancelled)
        #expect(workspace.activeTab === second)
        try await finishAutoSave(first)
        // The other tab may already have finished while the first task awaited its I/O.
        if second.autoSaveTask != nil { try await finishAutoSave(second) }
        #expect(try String(contentsOf: first.url, encoding: .utf8) == after)
        #expect(try String(contentsOf: second.url, encoding: .utf8) == "background-safe")
        #expect(!first.isDirty && !second.isDirty)
    }

    @Test func nativeUndoAndRedoRemainAvailableAfterAutoSave() async throws {
        _ = NSApplication.shared
        let workspace = Workspace(preferences: preferences, autoSaveDelay: .milliseconds(30))
        defer { clean(workspace) }
        workspace.autoSaveEnabled = true
        let tab = try await open(in: workspace)
        let editor = tab.sourceEditor()
        editor.textView.insertText(" edited", replacementRange: NSRange(location: 8, length: 0))
        try await finishAutoSave(tab)
        #expect(tab.canUndo && !tab.isDirty)
        workspace.undo()
        try await finishAutoSave(tab)
        #expect(try String(contentsOf: tab.url, encoding: .utf8) == "original")
        #expect(tab.canRedo && !tab.isDirty)
        workspace.redo()
        try await finishAutoSave(tab)
        #expect(try String(contentsOf: tab.url, encoding: .utf8) == "original edited")
    }

    @Test(arguments: [false, true])
    func externalConflictPausesWithoutPromptOrOverwrite(checked: Bool) async throws {
        let workspace = Workspace(preferences: preferences, autoSaveDelay: .milliseconds(40))
        defer { clean(workspace) }
        workspace.autoSaveEnabled = true
        let tab = try await open(in: workspace)
        var prompted = false
        workspace.chooseConflict = { _ in prompted = true; return .overwrite }
        tab.edit("my draft")
        try "external".write(to: tab.url, atomically: true, encoding: .utf8)
        if checked { await workspace.checkExternalChanges() }
        if tab.autoSaveTask != nil { try await finishAutoSave(tab) }
        #expect(!prompted && tab.externalChange && tab.isDirty)
        #expect(tab.draft == "my draft" && tab.autoSaveError != nil)
        #expect(try String(contentsOf: tab.url, encoding: .utf8) == "external")
        tab.edit("revised draft")
        #expect(tab.autoSaveTask == nil)
        #expect(await workspace.save(tab))
        #expect(prompted && tab.autoSaveError == nil)
        tab.edit("after manual resolution")
        try await finishAutoSave(tab)
        #expect(try String(contentsOf: tab.url, encoding: .utf8) == "after manual resolution")
    }

    @Test func missingFileIsNotRecreatedAutomatically() async throws {
        let workspace = Workspace(preferences: preferences, autoSaveDelay: .milliseconds(30))
        defer { clean(workspace) }
        workspace.autoSaveEnabled = true
        let tab = try await open(in: workspace)
        tab.edit("keep draft")
        try FileManager.default.removeItem(at: tab.url)
        try await finishAutoSave(tab)
        #expect(!FileManager.default.fileExists(atPath: tab.url.path))
        #expect(tab.draft == "keep draft" && tab.isDirty && tab.autoSaveError != nil)
    }

    @Test func failedWriteKeepsDraftAndPausesUntilManualSave() async throws {
        let workspace = Workspace(preferences: preferences, autoSaveDelay: .milliseconds(30))
        defer { clean(workspace) }
        workspace.autoSaveEnabled = true
        let tab = try await open(in: workspace)
        tab.edit("bad\0draft")
        try await finishAutoSave(tab)
        #expect(tab.isDirty && tab.autoSaveError != nil && workspace.notice != nil)
        #expect(try String(contentsOf: tab.url, encoding: .utf8) == "original")
        tab.edit("valid draft")
        #expect(tab.autoSaveTask == nil)
        #expect(await workspace.save(tab))
        #expect(tab.autoSaveError == nil && !tab.isDirty)
        tab.edit("another edit")
        try await finishAutoSave(tab)
        #expect(!tab.isDirty && tab.savedText == "another edit")
    }

    @Test func discardDuringCloseCancelsAutoSaveAndDetachesClosedTab() async throws {
        let workspace = Workspace(preferences: preferences, autoSaveDelay: .milliseconds(30))
        defer { clean(workspace) }
        workspace.autoSaveEnabled = true
        let tab = try await open(in: workspace)
        tab.edit("discard me")
        workspace.chooseUnsaved = { _ in
            try? await Task.sleep(for: .milliseconds(100))
            return .discard
        }
        workspace.close(tab.id)
        await tab.closeTask?.value
        #expect(workspace.tabs.isEmpty && tab.autoSaveTask == nil)
        tab.edit("late event from closed editor")
        #expect(tab.autoSaveTask == nil)
        #expect(try String(contentsOf: tab.url, encoding: .utf8) == "original")
    }

    @Test func newEditsDuringManualSaveAreAutoSavedAfterItFinishes() async throws {
        let workspace = Workspace(preferences: preferences, autoSaveDelay: .milliseconds(30))
        defer { clean(workspace) }
        workspace.autoSaveEnabled = true
        let tab = try await open(in: workspace)
        tab.edit("first draft")
        try "external".write(to: tab.url, atomically: true, encoding: .utf8)
        workspace.chooseConflict = { tab in
            tab.edit("newest draft")
            try? await Task.sleep(for: .milliseconds(100))
            return .overwrite
        }
        #expect(await workspace.save(tab))
        try await finishAutoSave(tab)
        #expect(!tab.isDirty && tab.savedText == "newest draft")
        #expect(try String(contentsOf: tab.url, encoding: .utf8) == "newest draft")
    }

    @Test func pendingAutoSaveFollowsRenameWithoutRecreatingOldPath() async throws {
        let workspace = Workspace(preferences: preferences, autoSaveDelay: .milliseconds(50))
        defer { clean(workspace) }
        workspace.autoSaveEnabled = true
        let tab = try await open(in: workspace)
        let original = tab.url
        tab.edit("renamed draft")
        let renamed = try await workspace.rename(FileEntry(url: original, isDirectory: false), to: "renamed.md")
        if tab.autoSaveTask != nil { try await finishAutoSave(tab) }
        #expect(!FileManager.default.fileExists(atPath: original.path))
        #expect(try String(contentsOf: renamed, encoding: .utf8) == "renamed draft")
        #expect(!tab.isDirty)
    }

    @Test func waitsForChineseCompositionToCommitBeforeWriting() async throws {
        _ = NSApplication.shared
        let workspace = Workspace(preferences: preferences, autoSaveDelay: .milliseconds(30))
        defer { clean(workspace) }
        workspace.autoSaveEnabled = true
        let tab = try await open(in: workspace)
        let editor = tab.sourceEditor()
        editor.textView.insertText(" edited", replacementRange: NSRange(location: 8, length: 0))
        editor.textView.setMarkedText("拼音", selectedRange: NSRange(location: 2, length: 0),
                                      replacementRange: NSRange(location: 15, length: 0))
        try #require(editor.textView.hasMarkedText())
        let pending = try #require(tab.autoSaveTask)
        await pending.value
        #expect(try String(contentsOf: tab.url, encoding: .utf8) == "original")
        #expect(tab.isDirty && tab.autoSaveTask != nil)
        editor.textView.insertText("拼音", replacementRange: editor.textView.markedRange())
        editor.textView.unmarkText()
        try await finishAutoSave(tab)
        #expect(try String(contentsOf: tab.url, encoding: .utf8) == "original edited拼音")
        #expect(!tab.isDirty)
    }

}
