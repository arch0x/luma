import Foundation
import Testing
@testable import Luma

@MainActor struct MarkdownReadingTests {
    let directory: URL
    let preferences: UserDefaults
    let domain = "local.luma.reading-tests.\(UUID().uuidString)"

    init() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        preferences = try #require(UserDefaults(suiteName: domain))
    }
    private func clean() {
        try? FileManager.default.removeItem(at: directory)
        preferences.removePersistentDomain(forName: domain)
    }
    private var location: MarkdownReadingLocation {
        .init(offset: 1234, progress: 0.4, blockKey: "chapter/P/abc/0", blockProgress: 0.25, headingID: "chapter", headingProgress: 0.3)
    }

    @Test func previewWidthDefaultsToPaperMeasureAndPersistsCustomSetting() {
        defer { clean() }
        let workspace = chineseWorkspace(preferences: preferences)
        #expect(!workspace.previewFullWidth && workspace.markdownPreviewWidth == 840)
        workspace.previewMaxWidth = 1400
        let restored = chineseWorkspace(preferences: preferences)
        #expect(restored.markdownPreviewWidth == 1400)
        restored.previewFullWidth = true
        #expect(restored.markdownPreviewWidth == 0)
        restored.previewFullWidth = false
        #expect(restored.markdownPreviewWidth == 1400)
        preferences.set(-100, forKey: "previewMaxWidth")
        #expect(chineseWorkspace(preferences: preferences).previewMaxWidth == 840)
    }

    @Test func typographyDefaultsPersistAndInvalidPreferencesRecover() throws {
        defer { clean() }
        let workspace = chineseWorkspace(preferences: preferences)
        #expect(workspace.markdownTypography == MarkdownTypography())
        workspace.markdownFont = .songti
        workspace.markdownFontSize = 22
        workspace.markdownLineHeight = 2.1
        let freshPreferences = try #require(UserDefaults(suiteName: domain))
        let restored = chineseWorkspace(preferences: freshPreferences)
        #expect(restored.markdownTypography == MarkdownTypography(font: .songti, fontSize: 22, lineHeight: 2.1))
        preferences.set("unknown-font", forKey: "markdownFont")
        preferences.set(200, forKey: "markdownFontSize")
        preferences.set(-1, forKey: "markdownLineHeight")
        #expect(chineseWorkspace(preferences: preferences).markdownTypography == MarkdownTypography())
        #expect(MarkdownTypography(fontSize: .nan, lineHeight: .infinity) == MarkdownTypography())
    }

    @Test func closingAndReopeningDocumentAndWorkspaceKeepReadingPosition() async throws {
        defer { clean() }
        let file = directory.appendingPathComponent("note.md")
        try "# Chapter".write(to: file, atomically: true, encoding: .utf8)
        let workspace = chineseWorkspace(preferences: preferences)
        workspace.open([file])
        let first = try #require(workspace.activeTab)
        await first.loadTask?.value
        first.rememberReadingPosition(location)
        workspace.close(first.id)
        workspace.open([file])
        let reopened = try #require(workspace.activeTab)
        #expect(reopened !== first)
        #expect(reopened.markdownLocation == location)
        await workspace.prepareForTermination()
        let restarted = chineseWorkspace(preferences: preferences)
        restarted.restore()
        let tab = try #require(restarted.activeTab)
        await tab.loadTask?.value
        #expect(tab.markdownLocation == location)
        #expect(tab.markdownOffset == 1234)
        await restarted.prepareForTermination()
    }

    @Test func bookmarksPersistDeduplicateAndRemoveAcrossHistoryInstances() throws {
        defer { clean() }
        let file = directory.appendingPathComponent("note.md")
        let alias = directory.appendingPathComponent("alias.md")
        try "# Chapter".write(to: file, atomically: true, encoding: .utf8)
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: file)
        let history = MarkdownReadingHistory(preferences: preferences)
        let session = history.session(for: file)
        let id = try #require(session.addBookmark(at: location, title: "Chapter"))
        #expect(session.addBookmark(at: location, title: "Duplicate") == id)
        #expect(session.bookmarks.count == 1)
        history.flush()
        let restoredHistory = MarkdownReadingHistory(preferences: preferences)
        let restored = restoredHistory.session(for: alias)
        #expect(restored.bookmarks.first?.title == "Chapter")
        #expect(restored.bookmarks.first?.location == location)
        restored.removeBookmark(id)
        restoredHistory.flush()
        #expect(MarkdownReadingHistory(preferences: preferences).session(for: file).bookmarks.isEmpty)
        #expect(try String(contentsOf: file, encoding: .utf8) == "# Chapter")
    }

    @Test func damagedRecordsAndNonfiniteLocationsRecoverSafely() {
        defer { clean() }
        let file = directory.appendingPathComponent("note.md")
        let key = MarkdownReadingHistory.storageKey(for: file)
        preferences.set(Data("broken".utf8), forKey: key)
        let history = MarkdownReadingHistory(preferences: preferences)
        let session = history.session(for: file)
        #expect(session.location == nil && session.bookmarks.isEmpty)
        session.remember(.init(offset: .nan, progress: 9, blockKey: nil, blockProgress: -2, headingID: nil, headingProgress: .infinity))
        history.flush()
        let restored = MarkdownReadingHistory(preferences: preferences).session(for: file)
        #expect(restored.location?.offset == 0)
        #expect(restored.location?.progress == 1)
        #expect(restored.location?.blockProgress == 0)
    }

    @Test func startupRestoresTabOrderSelectionAndSkipsMissingFiles() async throws {
        defer { clean() }
        let first = directory.appendingPathComponent("first.md")
        let second = directory.appendingPathComponent("second.md")
        let text = directory.appendingPathComponent("text.txt")
        for file in [first, second, text] { try "read".write(to: file, atomically: true, encoding: .utf8) }
        let workspace = chineseWorkspace(preferences: preferences)
        workspace.open([first, second, text])
        workspace.activeID = workspace.tabs[0].id
        for tab in workspace.tabs { await tab.loadTask?.value }
        try FileManager.default.removeItem(at: second)
        let restarted = chineseWorkspace(preferences: preferences)
        restarted.restore()
        #expect(restarted.tabs.map(\.title) == ["first.md", "text.txt"])
        #expect(restarted.activeTab?.title == "first.md")
        restarted.close(try #require(restarted.activeID))
        restarted.restore()
        #expect(restarted.tabs.map(\.title) == ["text.txt"])
        await restarted.prepareForTermination()
        for tab in restarted.tabs { await tab.loadTask?.value }
    }

    @Test func terminationWaitsForJustClosedTabsFinalCapture() async throws {
        defer { clean() }
        let file = directory.appendingPathComponent("note.md")
        try "read".write(to: file, atomically: true, encoding: .utf8)
        let workspace = chineseWorkspace(preferences: preferences)
        workspace.open([file])
        let tab = try #require(workspace.activeTab)
        await tab.loadTask?.value
        let final = location
        tab.captureMarkdownPosition = { [weak tab] in
            try? await Task.sleep(for: .milliseconds(40))
            tab?.rememberReadingPosition(final)
        }
        workspace.close(tab.id)
        await workspace.prepareForTermination()
        #expect(MarkdownReadingHistory(preferences: preferences).session(for: file).location == final)
        let restarted = chineseWorkspace(preferences: preferences)
        restarted.restore()
        #expect(restarted.tabs.isEmpty)
    }
}
