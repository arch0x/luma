import AppKit
import Testing
import ReaderCore
@testable import Luma

@MainActor struct DocumentEditingTests {
    let directory: URL
    let preferences: UserDefaults
    let domain = "local.luma.editing-tests.\(UUID().uuidString)"
    init() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        preferences = try #require(UserDefaults(suiteName: domain))
    }
    private func clean() {
        try? FileManager.default.removeItem(at: directory)
        preferences.removePersistentDomain(forName: domain)
    }
    private func open(_ text: String = "original", name: String = "note.txt", in workspace: Workspace) async throws -> DocumentTab {
        let file = directory.appendingPathComponent(name)
        try text.write(to: file, atomically: true, encoding: .utf8)
        workspace.open([file])
        let tab = try #require(workspace.activeTab)
        await tab.loadTask?.value
        return tab
    }

    @Test(arguments: ["md", "json", "csv", "tsv", "swift", "yaml", "txt"])
    func allTextFormatsEditPreviewAndSave(ext: String) async throws {
        defer { clean() }
        let workspace = Workspace(preferences: preferences)
        let before: String, after: String
        switch ext {
        case "json": before = #"{"count":1}"#; after = #"{"count":2}"#
        case "csv": before = "name,count\nold,1"; after = "name,count\n\"new,name\",2"
        case "tsv": before = "name\tcount\nold\t1"; after = "name\tcount\nnew\t2"
        case "md": before = "# Before"; after = "# After\n\n**edited**"
        default: before = "first"; after = "第二版 🙂\nnext"
        }
        let tab = try await open(before, name: "note.\(ext)", in: workspace)
        #expect(tab.canEdit && !tab.isDirty)
        tab.edit(after)
        await tab.previewTask?.value
        #expect(tab.isDirty && tab.draft == after)
        #expect(try String(contentsOf: tab.url, encoding: .utf8) == before)
        guard case .ready(let content) = tab.state else { Issue.record("Preview not ready"); return }
        #expect(content.source == after)
        if case .json(_, let root) = content { #expect(root.children?.first?.value == "2") }
        if case .table(_, let table) = content { #expect(table.rows.last?.last == "2") }
        #expect(await workspace.save(tab))
        #expect(!tab.isDirty)
        #expect(try String(contentsOf: tab.url, encoding: .utf8) == after)
    }

    @Test(arguments: ["json", "csv"])
    func invalidStructuredDraftCanBeSavedAndPreviewRecovers(ext: String) async throws {
        defer { clean() }
        let workspace = Workspace(preferences: preferences)
        let valid = ext == "json" ? #"{"n":1}"# : "name,count\na,1"
        let invalid = ext == "json" ? "{incomplete" : "name,count\n\"unfinished"
        let tab = try await open(valid, name: "note.\(ext)", in: workspace)
        tab.edit(invalid)
        await tab.previewTask?.value
        #expect(tab.previewError != nil && tab.draft == invalid)
        #expect(await workspace.save(tab))
        #expect(try String(contentsOf: tab.url, encoding: .utf8) == invalid)
        tab.edit(valid)
        await tab.previewTask?.value
        #expect(tab.previewError == nil && tab.isDirty)
    }

    @Test func nativeUndoSurvivesTabAndPreviewSwitchesAndTracksSavedContent() async throws {
        defer { clean() }
        _ = NSApplication.shared
        let workspace = Workspace(preferences: preferences)
        let tab = try await open("original 🙂", name: "note.md", in: workspace)
        let editor = tab.sourceEditor()
        editor.textView.setSelectedRange(NSRange(location: (editor.textView.string as NSString).length, length: 0))
        editor.textView.insertText(" edited", replacementRange: editor.textView.selectedRange())
        editor.textView.breakUndoCoalescing()
        #expect(tab.draft == "original 🙂 edited" && tab.isDirty && tab.canUndo)
        tab.showSource = false
        let second = try await open("other", name: "other.txt", in: workspace)
        workspace.activeID = tab.id
        tab.showSource = true
        #expect(tab.sourceEditor() === editor)
        workspace.undo()
        #expect(tab.draft == "original 🙂" && !tab.isDirty && tab.canRedo)
        workspace.redo()
        #expect(tab.draft == "original 🙂 edited" && tab.isDirty)
        #expect(await workspace.save(tab))
        workspace.undo()
        #expect(tab.isDirty && tab.draft == "original 🙂")
        #expect(second.draft == "other" && !second.isDirty)
        editor.textView.undoManager?.removeAllActions()
    }

    @Test func conflictCancelPreservesDraftAndExternalBytes() async throws {
        defer { clean() }
        let workspace = Workspace(preferences: preferences)
        let tab = try await open(in: workspace)
        tab.edit("my draft")
        try "external".write(to: tab.url, atomically: true, encoding: .utf8)
        await workspace.checkExternalChanges()
        #expect(tab.externalChange)
        workspace.chooseConflict = { _ in .cancel }
        #expect(await workspace.save(tab) == false)
        #expect(tab.draft == "my draft" && tab.isDirty)
        #expect(try String(contentsOf: tab.url, encoding: .utf8) == "external")
    }

    @Test func overwriteRechecksIfFileChangesDuringConflictDecision() async throws {
        defer { clean() }
        let workspace = Workspace(preferences: preferences)
        let tab = try await open(in: workspace)
        tab.edit("draft")
        try "second".write(to: tab.url, atomically: true, encoding: .utf8)
        var decisions = 0
        workspace.chooseConflict = { tab in
            decisions += 1
            if decisions == 1 {
                try? "third".write(to: tab.url, atomically: true, encoding: .utf8)
                return .overwrite
            }
            return .cancel
        }
        #expect(await workspace.save(tab) == false)
        #expect(decisions == 2 && tab.isDirty)
        #expect(try String(contentsOf: tab.url, encoding: .utf8) == "third")
        workspace.chooseConflict = { _ in .overwrite }
        #expect(await workspace.save(tab))
        #expect(try String(contentsOf: tab.url, encoding: .utf8) == "draft")
    }

    @Test func explicitReloadReplacesDraftAndClearsUndo() async throws {
        defer { clean() }
        _ = NSApplication.shared
        let workspace = Workspace(preferences: preferences)
        let tab = try await open(in: workspace)
        let editor = tab.sourceEditor()
        editor.textView.insertText("draft", replacementRange: NSRange(location: 0, length: 8))
        try "disk".write(to: tab.url, atomically: true, encoding: .utf8)
        workspace.chooseConflict = { _ in .reload }
        #expect(await workspace.save(tab) == false)
        #expect(tab.draft == "disk" && !tab.isDirty && !tab.externalChange)
        #expect(editor.textView.string == "disk" && !tab.canUndo)
    }

    @Test func failedReloadOrSaveKeepsEditedContent() async throws {
        defer { clean() }
        let workspace = Workspace(preferences: preferences)
        let tab = try await open(in: workspace)
        tab.edit("draft")
        try "external".write(to: tab.url, atomically: true, encoding: .utf8)
        workspace.chooseConflict = { tab in
            try? FileManager.default.removeItem(at: tab.url)
            return .reload
        }
        #expect(await workspace.save(tab) == false)
        #expect(tab.draft == "draft" && tab.isDirty && workspace.notice != nil)
        tab.edit("bad\0text")
        workspace.chooseUnsaved = { _ in .save }
        workspace.close(tab.id)
        await tab.closeTask?.value
        #expect(workspace.tabs.count == 1 && tab.isDirty)
    }

    @Test(arguments: [UnsavedChoice.cancel, .discard, .save])
    func closingDirtyTabHonorsChoice(choice: UnsavedChoice) async throws {
        defer { clean() }
        let workspace = Workspace(preferences: preferences)
        let tab = try await open(in: workspace)
        tab.edit("draft")
        workspace.chooseUnsaved = { _ in choice }
        workspace.close(tab.id)
        await tab.closeTask?.value
        #expect(workspace.tabs.isEmpty == (choice != .cancel))
        #expect(try String(contentsOf: tab.url, encoding: .utf8) == (choice == .save ? "draft" : "original"))
    }

    @Test func cancelQuitKeepsAllDraftsAndSuccessfulReviewSavesOrDiscards() async throws {
        defer { clean() }
        let workspace = Workspace(preferences: preferences)
        let first = try await open(in: workspace)
        let second = try await open("second", name: "second.txt", in: workspace)
        first.edit("first draft"); second.edit("second draft")
        workspace.chooseUnsaved = { $0 === first ? .discard : .cancel }
        #expect(await workspace.confirmCloseAll() == false)
        #expect(first.isDirty && second.isDirty)
        workspace.chooseUnsaved = { $0 === first ? .discard : .save }
        #expect(await workspace.confirmCloseAll())
        #expect(first.draft == "original" && !first.isDirty && !second.isDirty)
        #expect(try String(contentsOf: second.url, encoding: .utf8) == "second draft")
    }

    @Test func reloadRequiresDecisionAndDirectLoadNeverDiscardsDraft() async throws {
        defer { clean() }
        let workspace = Workspace(preferences: preferences)
        let tab = try await open(in: workspace)
        tab.edit("draft")
        workspace.load(tab)
        #expect(tab.draft == "draft" && tab.isDirty)
        workspace.chooseUnsaved = { _ in .cancel }
        #expect(await workspace.reload(tab) == false)
        #expect(tab.draft == "draft")
        workspace.chooseUnsaved = { _ in .discard }
        #expect(await workspace.reload(tab))
        #expect(tab.draft == "original" && !tab.isDirty)
    }

    @Test func editsMadeDuringSaveRemainDirty() async throws {
        defer { clean() }
        let workspace = Workspace(preferences: preferences)
        let tab = try await open(in: workspace)
        tab.edit("save this")
        try "external".write(to: tab.url, atomically: true, encoding: .utf8)
        workspace.chooseConflict = { tab in tab.edit("newer edit"); return .overwrite }
        #expect(await workspace.save(tab))
        #expect(tab.isDirty && tab.draft == "newer edit" && tab.savedText == "save this")
        #expect(try String(contentsOf: tab.url, encoding: .utf8) == "save this")
    }

    @Test func newEditsDuringFinalCloseCaptureCancelClosing() async throws {
        defer { clean() }
        let workspace = Workspace(preferences: preferences)
        let tab = try await open(in: workspace)
        tab.edit("reviewed draft")
        workspace.chooseUnsaved = { _ in .discard }
        tab.captureMarkdownPosition = { [weak tab] in
            await Task.yield()
            tab?.edit("new edit after decision")
        }
        #expect(await workspace.confirmCloseAll() == false)
        #expect(tab.draft == "new edit after decision" && tab.isDirty)
        #expect(try String(contentsOf: tab.url, encoding: .utf8) == "original")
    }
}
