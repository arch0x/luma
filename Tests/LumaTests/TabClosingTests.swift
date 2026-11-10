import AppKit
import ReaderCore
import Testing
@testable import Luma

@MainActor struct TabClosingTests {
    let directory: URL
    let preferences: UserDefaults
    let domain = "local.luma.tab-closing.\(UUID())"

    init() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        preferences = try #require(UserDefaults(suiteName: domain))
    }
    private func clean() {
        try? FileManager.default.removeItem(at: directory)
        preferences.removePersistentDomain(forName: domain)
    }
    private func open(_ count: Int = 5, in workspace: Workspace) async throws -> [DocumentTab] {
        let files = try (0..<count).map { index in
            let file = directory.appendingPathComponent("note-\(index).txt")
            try Data("original \(index)".utf8).write(to: file)
            return file
        }
        workspace.open(files)
        for tab in workspace.tabs { await tab.loadTask?.value }
        return workspace.tabs
    }

    @Test(arguments: TabCloseScope.allCases)
    func eachScopeUsesTheClickedTabAndPreservesTheCorrectSurvivors(scope: TabCloseScope) async throws {
        defer { clean() }
        let workspace = chineseWorkspace(preferences: preferences)
        let tabs = try await open(in: workspace)
        workspace.activeID = tabs[0].id
        let ids = workspace.tabIDs(toClose: scope, relativeTo: tabs[2].id)
        let expected: [URL]
        switch scope {
        case .current: expected = [tabs[0].id, tabs[1].id, tabs[3].id, tabs[4].id]
        case .others: expected = [tabs[2].id]
        case .left: expected = [tabs[2].id, tabs[3].id, tabs[4].id]
        case .right: expected = [tabs[0].id, tabs[1].id, tabs[2].id]
        case .all: expected = []
        }
        #expect(await workspace.closeTabs(ids))
        #expect(workspace.tabs.map(\.id) == expected)
        let expectedActive = scope == .all ? nil : expected.first
        #expect(workspace.activeID == expectedActive)
        #expect(preferences.stringArray(forKey: "openFileTabs") == expected.map(\.path))
    }

    @Test func emptySidesAndMissingContextDoNotCloseOtherFiles() async throws {
        defer { clean() }
        let workspace = chineseWorkspace(preferences: preferences)
        let tabs = try await open(in: workspace)
        #expect(workspace.tabIDs(toClose: .left, relativeTo: tabs[0].id).isEmpty)
        #expect(workspace.tabIDs(toClose: .right, relativeTo: tabs[4].id).isEmpty)
        #expect(workspace.tabIDs(toClose: .all, relativeTo: directory.appendingPathComponent("missing")).isEmpty)
        #expect(await workspace.closeTabs([]))
        #expect(workspace.tabs.count == 5)
    }

    @Test func cancellingLaterInTheReviewKeepsAllTabsDraftsAndUndo() async throws {
        defer { clean() }
        _ = NSApplication.shared
        let workspace = chineseWorkspace(preferences: preferences)
        let tabs = try await open(3, in: workspace)
        let editor = tabs[0].sourceEditor()
        editor.textView.insertText("edited ", replacementRange: NSRange(location: 0, length: 0))
        editor.textView.breakUndoCoalescing()
        tabs[2].edit("third draft")
        let selected = workspace.activeID
        var asked: [URL] = []
        workspace.chooseUnsaved = { tab in
            asked.append(tab.id)
            return tab === tabs[0] ? .discard : .cancel
        }
        #expect(await workspace.closeTabs(tabs.map(\.id)) == false)
        #expect(asked == [tabs[0].id, tabs[2].id])
        #expect(workspace.tabs.map(\.id) == tabs.map(\.id) && workspace.activeID == selected)
        #expect(tabs[0].draft == "edited original 0" && tabs[0].isDirty && tabs[0].canUndo)
        #expect(tabs[0].sourceEditor() === editor && tabs[2].draft == "third draft")
        #expect(workspace.canCloseTabs)
        editor.textView.undoManager?.removeAllActions()
    }

    @Test func saveAndDiscardApplyOnlyToTheChosenTargetsAndCaptureOnce() async throws {
        defer { clean() }
        let workspace = chineseWorkspace(preferences: preferences)
        let tabs = try await open(3, in: workspace)
        tabs[1].edit("save this"); tabs[2].edit("discard this")
        workspace.activeID = tabs[2].id
        workspace.chooseUnsaved = { $0 === tabs[1] ? .save : .discard }
        var captures = 0
        tabs[1].captureMarkdownPosition = { captures += 1 }
        tabs[2].captureMarkdownPosition = { captures += 1 }
        #expect(await workspace.closeTabs([tabs[1].id, tabs[2].id]))
        #expect(workspace.tabs.map(\.id) == [tabs[0].id] && workspace.activeID == tabs[0].id)
        #expect(captures == 2)
        #expect(try String(contentsOf: tabs[1].url, encoding: .utf8) == "save this")
        #expect(try String(contentsOf: tabs[2].url, encoding: .utf8) == "original 2")
    }

    @Test func failedSaveKeepsTheEntireRequestedGroupOpen() async throws {
        defer { clean() }
        let workspace = chineseWorkspace(preferences: preferences)
        let tabs = try await open(2, in: workspace)
        tabs[1].edit("invalid\0draft")
        workspace.chooseUnsaved = { _ in .save }
        #expect(await workspace.closeTabs(tabs.map(\.id)) == false)
        #expect(workspace.tabs.count == 2 && tabs[1].draft == "invalid\0draft")
        #expect(workspace.notice?.contains("无法保存") == true && workspace.canCloseTabs)
        #expect(try String(contentsOf: tabs[1].url, encoding: .utf8) == "original 1")
    }

    @Test func newEditsDuringPositionCaptureCancelTheWholeClose() async throws {
        defer { clean() }
        let workspace = chineseWorkspace(preferences: preferences)
        let tabs = try await open(2, in: workspace)
        tabs[0].edit("reviewed draft")
        workspace.chooseUnsaved = { _ in .discard }
        tabs[1].captureMarkdownPosition = { tabs[0].edit("newer draft") }
        #expect(await workspace.closeTabs(tabs.map(\.id)) == false)
        #expect(workspace.tabs.count == 2 && tabs[0].draft == "newer draft" && tabs[0].isDirty)
        #expect(workspace.notice?.contains("又有变化") == true)
    }

    @Test func tabsOpenedDuringReviewSurviveAndReentrantCloseIsBlocked() async throws {
        defer { clean() }
        let workspace = chineseWorkspace(preferences: preferences)
        let tabs = try await open(2, in: workspace)
        tabs[0].edit("draft")
        let newFile = directory.appendingPathComponent("new.txt")
        try Data("new file".utf8).write(to: newFile)
        workspace.chooseUnsaved = { _ in
            #expect(!workspace.canCloseTabs)
            workspace.close(tabs[1].id)
            #expect(workspace.tabs.count == 2)
            #expect(await workspace.closeTabs([tabs[1].id]) == false)
            workspace.open([newFile])
            await workspace.activeTab?.loadTask?.value
            return .discard
        }
        #expect(await workspace.closeTabs(tabs.map(\.id)))
        #expect(workspace.tabs.map(\.title) == ["new.txt"] && workspace.activeID == workspace.tabs.first?.id)
    }

    @Test func cancellingTheGroupRestartsAutoSaveForEarlierReviewedDrafts() async throws {
        defer { clean() }
        let workspace = chineseWorkspace(preferences: preferences, autoSaveDelay: .milliseconds(40))
        let tabs = try await open(2, in: workspace)
        tabs[0].edit("first draft"); tabs[1].edit("second draft")
        workspace.autoSaveEnabled = true
        workspace.chooseUnsaved = { $0 === tabs[0] ? .discard : .cancel }
        #expect(await workspace.closeTabs(tabs.map(\.id)) == false)
        let deadline = ContinuousClock.now + .seconds(5)
        while tabs.contains(where: \.isDirty) && ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(20)) }
        #expect(workspace.tabs.count == 2 && tabs.allSatisfy { !$0.isDirty })
        #expect(try String(contentsOf: tabs[0].url, encoding: .utf8) == "first draft")
    }
}
