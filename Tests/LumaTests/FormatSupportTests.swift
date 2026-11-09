import AppKit
import ReaderCore
import Testing
@testable import Luma

@MainActor struct FormatSupportTests {
    let directory: URL
    let preferences: UserDefaults
    let domain = "local.luma.format-tests.\(UUID().uuidString)"

    init() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        preferences = try #require(UserDefaults(suiteName: domain))
    }
    private func clean() {
        try? FileManager.default.removeItem(at: directory)
        preferences.removePersistentDomain(forName: domain)
    }
    private func open(_ source: String, name: String, in workspace: Workspace) async throws -> DocumentTab {
        let file = directory.appendingPathComponent(name)
        try Data(source.utf8).write(to: file)
        workspace.open([file])
        let tab = try #require(workspace.activeTab)
        await tab.loadTask?.value
        return tab
    }

    @Test func fallbackSupportsFindEditingUndoSaveRenameAndReopen() async throws {
        defer { clean() }
        _ = NSApplication.shared
        let workspace = Workspace(preferences: preferences)
        let tab = try await open("original\n", name: "note.luma-custom", in: workspace)
        #expect(tab.kind == .text && tab.formatLabel == "纯文本" && !tab.hasPreview && workspace.canFind)
        let editor = tab.sourceEditor()
        editor.textView.insertText("edited ", replacementRange: NSRange(location: 0, length: 0))
        editor.textView.breakUndoCoalescing()
        #expect(tab.isDirty && tab.canUndo)
        _ = try await workspace.rename(FileEntry(url: tab.url, isDirectory: false), to: "renamed.luma-custom")
        #expect(tab.sourceEditor() === editor && tab.canUndo && tab.canEdit)
        #expect(await workspace.save(tab))
        #expect(try String(contentsOf: tab.url, encoding: .utf8) == "edited original\n")
        let reopened = Workspace(preferences: preferences)
        reopened.open([tab.url])
        let fresh = try #require(reopened.activeTab)
        await fresh.loadTask?.value
        #expect(fresh.kind == .text && fresh.canEdit && fresh.draft == "edited original\n")
    }

    @Test(arguments: ["jsonc", "jsonl", "ndjson"])
    func jsonVariantsOfferTheirOwnPreviewAndKeepOriginalSource(ext: String) async throws {
        defer { clean() }
        let source = ext == "jsonc" ? "// comment\n{\"ready\": true,}" : "{\"id\":1}\n{\"id\":2}\n"
        let tab = try await open(source, name: "data.\(ext)", in: Workspace(preferences: preferences))
        #expect(tab.kind == .text && tab.canEdit && tab.previewError == nil && tab.draft == source)
        #expect(tab.hasPreview && tab.codeLanguage?.identifier == ext && tab.codeLanguage?.isJSONFamily == true)
        #expect(!tab.showSource && tab.formatLabel == ext.uppercased())
    }

    @Test func binaryFilesNeverBecomeEditableAndTextDetectionRunsOnReload() async throws {
        defer { clean() }
        let workspace = Workspace(preferences: preferences)
        let archive = try await open("PK", name: "archive.zip", in: workspace)
        #expect(!archive.canEdit && archive.kind == .unsupported)
        let tab = try await open("text", name: "note.luma-custom", in: workspace)
        #expect(tab.canEdit)
        let binary = Data("bplist00data".utf8)
        try binary.write(to: tab.url)
        workspace.load(tab)
        await tab.loadTask?.value
        #expect(tab.draft == "text" && !tab.isDirty)
        #expect(workspace.notice?.contains("二进制") == true)
        #expect(try Data(contentsOf: tab.url) == binary)
        let blocked = try await open("bplist00data", name: "binary.luma-custom", in: workspace)
        #expect(!blocked.canEdit && blocked.draft == nil)
    }

    @Test func svgDraftPreviewAndSaveRecoverAfterInvalidXML() async throws {
        defer { clean() }
        let source = #"<svg xmlns="http://www.w3.org/2000/svg" width="200" height="100"><rect width="100" height="100" fill="blue"/></svg>"#
        let workspace = Workspace(preferences: preferences)
        let tab = try await open(source, name: "drawing.svg", in: workspace)
        #expect(tab.kind == .svg && tab.hasPreview && tab.canEdit && !tab.showSource && tab.formatLabel == "SVG")
        guard case .ready(.svg(let original)) = tab.state else { Issue.record("Missing SVG preview"); return }
        #expect(original == source)
        tab.edit("<svg")
        await tab.previewTask?.value
        #expect(tab.previewError != nil && tab.draft == "<svg")
        #expect(await workspace.save(tab))
        tab.edit(source.replacingOccurrences(of: "blue", with: "red"))
        await tab.previewTask?.value
        #expect(tab.previewError == nil && tab.isDirty)
        guard case .ready(.svg(let changed)) = tab.state else { Issue.record("SVG did not recover"); return }
        #expect(changed.contains("red"))
        #expect(await workspace.save(tab))
        #expect(try String(contentsOf: tab.url, encoding: .utf8) == changed)
    }

    @Test func invalidSVGOpensEditableSourceAndOversizedPreviewKeepsSource() async throws {
        defer { clean() }
        let workspace = Workspace(preferences: preferences)
        let broken = try await open("<svg", name: "broken.svg", in: workspace)
        #expect(broken.canEdit && broken.showSource && broken.previewError != nil && broken.draft == "<svg")
        let largeSource = #"<svg xmlns="http://www.w3.org/2000/svg"><!--"# + String(repeating: "x", count: SVGDocument.previewLimit) + "--></svg>"
        let large = try await open(largeSource, name: "large.svg", in: workspace)
        #expect(large.canEdit && large.showSource && large.previewError?.contains("1 MB") == true)
        #expect(large.draft == largeSource)
    }
}
