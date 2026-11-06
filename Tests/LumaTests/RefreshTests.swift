import AppKit
import SwiftUI
import Testing
@testable import Luma

@MainActor @Suite(.serialized) struct RefreshTests {
    let directory: URL
    let preferences: UserDefaults
    let domain = "local.luma.refresh-tests.\(UUID().uuidString)"

    init() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        preferences = try #require(UserDefaults(suiteName: domain))
    }
    private func clean() {
        try? FileManager.default.removeItem(at: directory)
        preferences.removePersistentDomain(forName: domain)
    }
    private func waitForTree(_ workspace: Workspace) async throws {
        let deadline = ContinuousClock.now + .seconds(5)
        while (!workspace.loadingDirectories.isEmpty || workspace.searching) && ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        try #require(workspace.loadingDirectories.isEmpty && !workspace.searching)
    }
    private func openDocument(in workspace: Workspace) async throws -> DocumentTab {
        let file = directory.appendingPathComponent("note.txt")
        try "original".write(to: file, atomically: true, encoding: .utf8)
        workspace.open([file])
        let tab = try #require(workspace.activeTab)
        await tab.loadTask?.value
        return tab
    }
    private func write(_ name: String, text: String = "external") throws {
        try text.write(to: directory.appendingPathComponent(name), atomically: true, encoding: .utf8)
    }
    private func names(_ folder: URL, in workspace: Workspace) -> Set<String> {
        Set(workspace.directories[folder]?.map(\.name) ?? [])
    }

    @Test func startupReadsFreshContentsAndCountsAsFirstAutomaticRefresh() async throws {
        defer { clean() }
        preferences.set([directory.path], forKey: "workspaceFolders")
        try write("added-before-launch.md")
        let workspace = Workspace(preferences: preferences)
        workspace.restore()
        try await waitForTree(workspace)
        let root = try #require(workspace.roots.first)
        #expect(names(root, in: workspace).contains("added-before-launch.md"))
        let now = ContinuousClock.now
        #expect(!workspace.refreshDirectoriesAutomatically(at: now))
        try write("added-after-launch.md")
        #expect(!workspace.refreshDirectoriesAutomatically(at: now.advanced(by: .seconds(29))))
        #expect(!names(root, in: workspace).contains("added-after-launch.md"))
        #expect(workspace.refreshDirectoriesAutomatically(at: now.advanced(by: .seconds(30))))
        try await waitForTree(workspace)
        #expect(names(root, in: workspace).contains("added-after-launch.md"))
    }

    @Test func thirtySecondBoundaryUpdatesCachedCollapsedFoldersAndRenames() async throws {
        defer { clean() }
        let child = directory.appendingPathComponent("Nested", isDirectory: true)
        try FileManager.default.createDirectory(at: child, withIntermediateDirectories: false)
        let workspace = Workspace(preferences: preferences)
        workspace.roots = [directory]
        workspace.loadDirectory(child)
        try await waitForTree(workspace)
        let start = ContinuousClock.now
        #expect(workspace.refreshDirectoriesAutomatically(at: start))
        try await waitForTree(workspace)
        try write("new-root.txt")
        try "new".write(to: child.appendingPathComponent("new-child.txt"), atomically: true, encoding: .utf8)
        #expect(!workspace.refreshDirectoriesAutomatically(at: start.advanced(by: .milliseconds(29_999))))
        #expect(workspace.loadingDirectories.isEmpty)
        #expect(!names(directory, in: workspace).contains("new-root.txt"))
        #expect(workspace.refreshDirectoriesAutomatically(at: start.advanced(by: .seconds(30))))
        try await waitForTree(workspace)
        #expect(names(directory, in: workspace).contains("new-root.txt"))
        #expect(names(child, in: workspace).contains("new-child.txt"))
        #expect(!workspace.expanded.contains(child))
        try FileManager.default.moveItem(at: directory.appendingPathComponent("new-root.txt"), to: directory.appendingPathComponent("renamed.txt"))
        try FileManager.default.removeItem(at: child.appendingPathComponent("new-child.txt"))
        #expect(!workspace.refreshDirectoriesAutomatically(at: start.advanced(by: .seconds(59))))
        #expect(workspace.refreshDirectoriesAutomatically(at: start.advanced(by: .seconds(60))))
        try await waitForTree(workspace)
        #expect(names(directory, in: workspace).contains("renamed.txt"))
        #expect(!names(directory, in: workspace).contains("new-root.txt"))
        #expect(names(child, in: workspace).isEmpty)
    }

    @Test(arguments: [false, true])
    func automaticRefreshDoesNotReloadOrPromptForOpenDocument(dirty: Bool) async throws {
        defer { clean() }
        let workspace = Workspace(preferences: preferences)
        workspace.roots = [directory]
        let tab = try await openDocument(in: workspace)
        if dirty { tab.edit("draft") }
        workspace.chooseUnsaved = { _ in Issue.record("Automatic tree refresh must not ask to discard edits"); return .cancel }
        let start = ContinuousClock.now
        #expect(workspace.refreshDirectoriesAutomatically(at: start))
        try await waitForTree(workspace)
        try write("note.txt", text: "disk changed")
        try write("new.txt")
        #expect(workspace.refreshDirectoriesAutomatically(at: start.advanced(by: .seconds(30))))
        try await waitForTree(workspace)
        #expect(names(directory, in: workspace).contains("new.txt"))
        #expect(tab.draft == (dirty ? "draft" : "original"))
        #expect(tab.isDirty == dirty)
    }

    @Test func manualRefreshUpdatesTreeContentAndSearchImmediatelyTwice() async throws {
        defer { clean() }
        let workspace = Workspace(preferences: preferences)
        workspace.roots = [directory]
        let tab = try await openDocument(in: workspace)
        workspace.query = "needle"
        let start = ContinuousClock.now
        #expect(workspace.refreshDirectoriesAutomatically(at: start))
        try await waitForTree(workspace)
        for number in 1...2 {
            try write("note.txt", text: "external \(number)")
            try write("needle-\(number).md")
            workspace.refresh()
            await workspace.refreshTask?.value
            try await waitForTree(workspace)
            #expect(tab.draft == "external \(number)")
            #expect(names(directory, in: workspace).contains("needle-\(number).md"))
            #expect(workspace.searchResults.contains { $0.name == "needle-\(number).md" })
        }
        #expect(!workspace.refreshDirectoriesAutomatically(at: start.advanced(by: .seconds(29))))
        #expect(workspace.refreshDirectoriesAutomatically(at: start.advanced(by: .seconds(30))))
        try await waitForTree(workspace)
    }

    @Test func cancellingDocumentReloadStillRefreshesDirectory() async throws {
        defer { clean() }
        let workspace = Workspace(preferences: preferences)
        workspace.roots = [directory]
        let tab = try await openDocument(in: workspace)
        tab.edit("unsaved draft")
        workspace.chooseUnsaved = { _ in .cancel }
        #expect(workspace.refreshDirectoriesAutomatically())
        try await waitForTree(workspace)
        try write("note.txt", text: "external")
        try write("added.txt")
        workspace.refresh()
        await workspace.refreshTask?.value
        try await waitForTree(workspace)
        #expect(names(directory, in: workspace).contains("added.txt"))
        #expect(tab.draft == "unsaved draft" && tab.isDirty)
        #expect(try String(contentsOf: tab.url, encoding: .utf8) == "external")
        workspace.chooseUnsaved = { _ in .discard }
        workspace.refresh()
        await workspace.refreshTask?.value
        #expect(tab.draft == "external" && !tab.isDirty)
    }

    @Test func manualRefreshWorksWithoutOpenDocument() async throws {
        defer { clean() }
        let workspace = Workspace(preferences: preferences)
        workspace.roots = [directory]
        #expect(workspace.refreshDirectoriesAutomatically())
        try await waitForTree(workspace)
        try write("added.txt")
        workspace.refresh()
        try await waitForTree(workspace)
        #expect(names(directory, in: workspace).contains("added.txt"))
        #expect(workspace.tabs.isEmpty && workspace.refreshTask == nil)
    }

    @Test func applicationActivationNotificationRefreshesAndThrottlesActualView() async throws {
        defer { clean() }
        _ = NSApplication.shared
        let workspace = Workspace(preferences: preferences)
        workspace.roots = [directory]
        let tab = try await openDocument(in: workspace)
        tab.edit("unsaved draft")
        workspace.loadDirectory(directory)
        try await waitForTree(workspace)
        let view = NSHostingView(rootView: WorkspaceView(workspace: workspace))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1180, height: 780), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = view
        defer { window.delegate = nil; window.close() }
        view.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(100))
        try write("activation-added.txt")
        // This is Luma's generic activation event; there is no Finder-specific condition.
        NotificationCenter.default.post(name: NSApplication.didBecomeActiveNotification, object: NSApplication.shared)
        try await waitForTree(workspace)
        #expect(names(directory, in: workspace).contains("activation-added.txt"))
        #expect(tab.draft == "unsaved draft" && tab.isDirty)
        try write("cooldown-added.txt")
        NotificationCenter.default.post(name: NSApplication.didBecomeActiveNotification, object: NSApplication.shared)
        try await Task.sleep(for: .milliseconds(20))
        #expect(!names(directory, in: workspace).contains("cooldown-added.txt"))
    }
}
