import AppKit
import PDFKit
import Testing
@testable import Luma

@MainActor struct WorkspaceTests {
    let directory: URL
    let preferences: UserDefaults
    let domain = "local.luma.tests.\(UUID().uuidString)"

    init() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        preferences = try #require(UserDefaults(suiteName: domain))
    }

    private func clean() {
        try? FileManager.default.removeItem(at: directory)
        preferences.removePersistentDomain(forName: domain)
    }

    @Test func opensRealFilesAndDeduplicatesTabs() async throws {
        defer { clean() }
        let workspace = Workspace(preferences: preferences)
        let first = directory.appendingPathComponent("first.md")
        let second = directory.appendingPathComponent("second.json")
        try "# Local document".write(to: first, atomically: true, encoding: .utf8)
        try #"{"enabled":true}"#.write(to: second, atomically: true, encoding: .utf8)
        workspace.open([first, second, first])
        #expect(workspace.tabs.count == 2)
        #expect(workspace.activeID == first.resolvingSymlinksInPath().standardizedFileURL)
        for tab in workspace.tabs { await tab.loadTask?.value }
        guard case .ready(.markdown(let source)) = workspace.tabs[0].state else {
            Issue.record("Markdown did not load"); return
        }
        #expect(source == "# Local document")
        guard case .ready(.json(_, let root)) = workspace.tabs[1].state else {
            Issue.record("JSON did not load"); return
        }
        #expect(root.children?.first?.value == "true")
        workspace.close(first.resolvingSymlinksInPath().standardizedFileURL)
        #expect(workspace.activeID == second.resolvingSymlinksInPath().standardizedFileURL)
        workspace.close(second.resolvingSymlinksInPath().standardizedFileURL)
        #expect(workspace.activeID == nil)
        #expect(workspace.tabs.isEmpty)
    }

    @Test func invalidJSONKeepsOriginalSource() async throws {
        defer { clean() }
        let workspace = Workspace(preferences: preferences)
        let file = directory.appendingPathComponent("broken.json")
        try "{broken".write(to: file, atomically: true, encoding: .utf8)
        workspace.open([file])
        let tab = try #require(workspace.activeTab)
        await tab.loadTask?.value
        guard case .ready(.text(let source)) = tab.state else {
            Issue.record("Invalid JSON lost source access"); return
        }
        #expect(source == "{broken")
        #expect(tab.showSource)
        #expect(workspace.notice != nil)
    }

    @Test func missingFileCanRecoverAfterReload() async throws {
        defer { clean() }
        let workspace = Workspace(preferences: preferences)
        let file = directory.appendingPathComponent("missing.txt")
        workspace.open([file])
        let tab = try #require(workspace.activeTab)
        await tab.loadTask?.value
        guard case .ready(.failed) = tab.state else { Issue.record("Missing file should show an error"); return }
        try "restored".write(to: file, atomically: true, encoding: .utf8)
        workspace.load(tab)
        await tab.loadTask?.value
        guard case .ready(.text(let source)) = tab.state else { Issue.record("Retry should recover"); return }
        #expect(source == "restored")
    }

    @Test func removingFolderKeepsOpenDocumentAndRestoresOtherRoots() async throws {
        defer { clean() }
        let workspace = Workspace(preferences: preferences)
        let file = directory.appendingPathComponent("note.txt")
        try "read only".write(to: file, atomically: true, encoding: .utf8)
        workspace.addFolder(directory)
        workspace.addFolder(directory)
        workspace.open([file])
        #expect(workspace.roots.count == 1)
        let restored = Workspace(preferences: preferences)
        restored.restore()
        #expect(restored.roots == workspace.roots)
        workspace.removeFolder(directory)
        #expect(workspace.roots.isEmpty)
        #expect(workspace.tabs.count == 1)
        await workspace.activeTab?.loadTask?.value
        #expect(try String(contentsOf: file, encoding: .utf8) == "read only")
    }

    @Test func fileSearchFindsNamesAndSkipsBuildFolders() async throws {
        defer { clean() }
        let file = directory.appendingPathComponent("target-note.md")
        let build = directory.appendingPathComponent("node_modules")
        try FileManager.default.createDirectory(at: build, withIntermediateDirectories: true)
        try "a".write(to: file, atomically: true, encoding: .utf8)
        try "b".write(to: build.appendingPathComponent("target-hidden.md"), atomically: true, encoding: .utf8)
        let service = FileService()
        let matches = try await service.search("TARGET", roots: [directory])
        #expect(matches.map { $0.url.resolvingSymlinksInPath() } == [file.resolvingSymlinksInPath()])
    }

    @Test func sampleWorkspaceContainsValidNativeMedia() throws {
        defer { clean() }
        let workspace = Workspace(preferences: preferences)
        let samples = try #require(workspace.samplesURL)
        let image = try #require(NSImage(contentsOf: samples.appendingPathComponent("留白.png")))
        #expect(image.size.width == 1200)
        let pdf = try #require(PDFDocument(url: samples.appendingPathComponent("阅读空间.pdf")))
        #expect(pdf.pageCount == 2)
        #expect(pdf.string?.contains("clarity") == true)
    }

    @Test func markdownImageRootUsesMostSpecificContainingWorkspace() throws {
        defer { clean() }
        let workspace = Workspace(preferences: preferences)
        let docs = directory.appendingPathComponent("docs", isDirectory: true)
        let file = docs.appendingPathComponent("note.md")
        #expect(workspace.imageRoot(for: file) == docs)
        workspace.roots = [directory]
        #expect(workspace.imageRoot(for: file) == directory)
        workspace.roots.append(docs)
        #expect(workspace.imageRoot(for: file) == docs)
        let other = directory.appendingPathComponent("docs-other/note.md")
        #expect(workspace.imageRoot(for: other) == directory)
    }

    @Test func markdownFindOpensAndAdvancesWithoutSwitchingToSource() {
        defer { clean() }
        let workspace = Workspace(preferences: preferences)
        let tab = DocumentTab(url: directory.appendingPathComponent("note.md"))
        workspace.tabs = [tab]; workspace.activeID = tab.id
        workspace.openFind()
        workspace.openFind()
        #expect(workspace.showFind && workspace.findFocusRequest == 2)
        #expect(!tab.showSource)
        tab.markdownFind.setQuery("test")
        tab.markdownFind.apply(["count": 2, "current": 1])
        #expect(workspace.canFindNext && workspace.canFindPrevious)
        workspace.advanceFind(-1)
        #expect(tab.markdownFind.direction == -1 && tab.markdownFind.busy)
        #expect(!tab.showSource)
    }
}
