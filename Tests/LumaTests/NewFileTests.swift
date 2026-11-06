import AppKit
import Testing
import ReaderCore
@testable import Luma

@MainActor struct NewFileTests {
    let directory: URL
    let preferences: UserDefaults
    let domain = "local.luma.new-file-tests.\(UUID().uuidString)"

    init() throws {
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
        directory = temporary.resolvingSymlinksInPath().standardizedFileURL
        preferences = try #require(UserDefaults(suiteName: domain))
    }
    private func clean() {
        try? FileManager.default.removeItem(at: directory)
        preferences.removePersistentDomain(forName: domain)
    }
    private func waitForDirectory(_ folder: URL, in workspace: Workspace) async throws {
        let deadline = ContinuousClock.now + .seconds(5)
        while workspace.loadingDirectories.contains(folder) && ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        try #require(!workspace.loadingDirectories.contains(folder))
        try #require(workspace.directoryErrors[folder] == nil)
    }

    @Test(arguments: [false, true])
    func createRefreshOpenEditAndSaveInSelectedFolder(nested: Bool) async throws {
        defer { clean() }
        _ = NSApplication.shared
        let folder = nested ? directory.appendingPathComponent("子目录") : directory
        if nested { try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false) }
        let workspace = Workspace(preferences: preferences)
        workspace.roots = [directory]
        workspace.loadDirectory(folder)
        try await waitForDirectory(folder, in: workspace)
        #expect(workspace.directories[folder]?.isEmpty == true)
        let file = try await workspace.createFile(named: "阅读 计划.md", in: folder)
        let tab = try #require(workspace.activeTab)
        await tab.loadTask?.value
        try await waitForDirectory(folder, in: workspace)
        #expect(workspace.expanded.contains(folder))
        #expect(workspace.directories[folder]?.contains { $0.url.resolvingSymlinksInPath() == file.resolvingSymlinksInPath() } == true)
        #expect(tab.url == file && tab.showSource && tab.canEdit && !tab.isDirty)
        #expect(tab.draft == "")
        tab.edit("# 新文档\n\n开始写作。")
        #expect(await workspace.save(tab))
        #expect(try String(contentsOf: file, encoding: .utf8) == "# 新文档\n\n开始写作。")
    }

    @Test func duplicateKeepsExistingBytesAndUnsavedTab() async throws {
        defer { clean() }
        let file = directory.appendingPathComponent("existing.md")
        try "original".write(to: file, atomically: true, encoding: .utf8)
        let workspace = Workspace(preferences: preferences)
        workspace.open([file])
        let tab = try #require(workspace.activeTab)
        await tab.loadTask?.value
        tab.edit("unsaved draft")
        do {
            _ = try await workspace.createFile(named: "existing.md", in: directory)
            Issue.record("Creation should fail for an existing file")
        } catch { #expect(error as? FileCreationError == .alreadyExists("existing.md")) }
        #expect(workspace.activeTab === tab && workspace.tabs.count == 1)
        #expect(tab.draft == "unsaved draft" && tab.isDirty)
        #expect(try String(contentsOf: file, encoding: .utf8) == "original")
    }

    @Test func concurrentCreatesRefreshAnAlreadyLoadingDirectoryAndSearch() async throws {
        defer { clean() }
        let workspace = Workspace(preferences: preferences)
        workspace.roots = [directory]
        workspace.query = "new"
        workspace.loadDirectory(directory)
        async let first = workspace.createFile(named: "new-a.txt", in: directory)
        async let second = workspace.createFile(named: "new-b.txt", in: directory)
        let created = try await [first, second]
        for tab in workspace.tabs { await tab.loadTask?.value }
        try await waitForDirectory(directory, in: workspace)
        let deadline = ContinuousClock.now + .seconds(5)
        while workspace.searching && ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(10)) }
        #expect(Set(workspace.directories[directory]?.map { $0.url.resolvingSymlinksInPath() } ?? []) == Set(created.map { $0.resolvingSymlinksInPath() }))
        #expect(Set(workspace.searchResults.map { $0.url.resolvingSymlinksInPath() }) == Set(created.map { $0.resolvingSymlinksInPath() }))
        #expect(workspace.tabs.count == 2)
    }
}
