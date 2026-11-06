import AppKit
import WebKit
import SwiftUI
import Testing
@testable import Luma

@MainActor @Suite(.serialized) struct CodePreviewTests {
    @MainActor struct Preview {
        let view: WKWebView
        let coordinator: MarkdownWebView.Coordinator
        let state: MarkdownRenderState
        var tab: DocumentTab { coordinator.tab }
        func value(_ script: String) async throws -> Any? { try await view.evaluateJavaScript(script) }
        func close() { MarkdownWebView.dismantleNSView(view, coordinator: coordinator) }
        func snapshot(_ name: String) async throws {
            guard let path = ProcessInfo.processInfo.environment["LUMA_CODE_PREVIEW_DIR"] else { return }
            let image = try await view.takeSnapshot(configuration: nil)
            let bitmap = try #require(image.tiffRepresentation.flatMap(NSBitmapImageRep.init(data:)))
            let png = try #require(bitmap.representation(using: .png, properties: [:]))
            let directory = URL(fileURLWithPath: path)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try png.write(to: directory.appendingPathComponent(name + ".png"))
        }
    }
    private func render(_ source: String, name: String = "sample.swift", dark: Bool = false) async throws -> Preview {
        _ = NSApplication.shared
        let tab = DocumentTab(url: URL(fileURLWithPath: "/tmp/\(name)"))
        tab.draft = source; tab.savedText = source
        let state = MarkdownRenderState()
        let coordinator = MarkdownWebView.Coordinator(source: source, tab: tab, dark: dark, state: state, onOpen: { _ in })
        let view = MarkdownWebView.makeWebView(coordinator: coordinator)
        view.frame = NSRect(x: 0, y: 0, width: 1000, height: 650)
        let preview = Preview(view: view, coordinator: coordinator, state: state)
        let deadline = ContinuousClock.now + .seconds(20)
        while state.loading && ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(20)) }
        guard !state.loading && state.error == nil else {
            preview.close()
            throw NSError(domain: "CodePreviewTests", code: 1, userInfo: [NSLocalizedDescriptionKey: state.error ?? "Timed out"])
        }
        return preview
    }

    @Test(arguments: [
        ("swift", "Swift", "// 本地阅读\nstruct Note { let title = \"Luma\" }\n"),
        ("py", "Python", "# 本地阅读\ndef greet(name):\n    return f\"Hello {name}\"\n"),
        ("js", "JavaScript", "const message = \"Luma\";\n"),
        ("ts", "TypeScript", "interface Note { title: string }\n"),
        ("rs", "Rust", "fn main() { let name = \"Luma\"; }\n"),
        ("go", "Go", "package main\nfunc main() { println(\"Luma\") }\n"),
        ("cpp", "C++", "int main() { return 42; }\n"),
        ("yaml", "YAML", "name: Luma\nenabled: true\n")
    ])
    func codeFilesHighlightAndKeepExactSourceAndLanguage(ext: String, title: String, source: String) async throws {
        let preview = try await render(source, name: "note.\(ext)")
        defer { preview.close() }
        #expect(preview.tab.hasPreview && !preview.tab.showSource && preview.tab.formatLabel == title)
        #expect(preview.state.metrics["highlighted"] == 1)
        #expect(try await preview.value("document.querySelector('pre code').textContent") as? String == source)
        #expect(try await preview.value("document.querySelector('.code-language').textContent") as? String == title)
        #expect(try await preview.value("document.querySelectorAll('pre code span').length > 0") as? Bool == true)
        #expect(!preview.tab.isDirty)
    }

    @Test func previewKeepsHTMLMarkdownBackticksAndFormulasLiteral() async throws {
        let source = "\"</code><script>window.executed = true</script><img src='https://example.invalid/a'>\"\n# heading\n```swift\nlet x = 1\n```\n$E=mc^2$\n\n"
        let preview = try await render(source, name: "literal.py")
        defer { preview.close() }
        #expect(try await preview.value("document.querySelector('pre code').textContent") as? String == source)
        #expect(try await preview.value("document.querySelectorAll('main script, main img, main h1, main .katex').length") as? Int == 0)
        #expect(try await preview.value("window.executed === undefined") as? Bool == true)
        #expect(preview.state.metrics["formulas"] == 0 && preview.state.metrics["images"] == 0)
    }

    @Test func themeAndLanguageChangesUpdatePreviewAndPreserveDraftAndPosition() async throws {
        let source = String(repeating: "let title = \"Luma\" // 中文🙂\n", count: 100)
        let preview = try await render(source)
        defer { preview.close() }
        try await preview.snapshot("code-light")
        let light = try await preview.value("getComputedStyle(document.querySelector('.hljs-keyword')).color") as? String
        _ = try await preview.value("window.scrollTo(0, 700)")
        let deadline = ContinuousClock.now + .seconds(2)
        while preview.tab.markdownOffset < 600 && ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(20)) }
        let offset = preview.tab.markdownOffset
        #expect(offset > 600)
        preview.tab.edit(source + "let edited = true\n")
        preview.coordinator.source = try #require(preview.tab.draft)
        preview.coordinator.dark = true
        preview.coordinator.renderIfNeeded()
        await preview.coordinator.renderTask?.value
        try await preview.snapshot("code-dark")
        #expect(try await preview.value("document.documentElement.dataset.theme") as? String == "dark")
        #expect(try await preview.value("getComputedStyle(document.querySelector('.hljs-keyword')).color") as? String != light)
        #expect(try await preview.value("document.querySelector('pre code').textContent") as? String == preview.tab.draft)
        #expect(abs((try await preview.value("window.scrollY") as? Double ?? 0) - offset) < 2)
        preview.tab.relocate(to: URL(fileURLWithPath: "/tmp/renamed.py"), readingSession: nil)
        preview.coordinator.renderIfNeeded()
        await preview.coordinator.renderTask?.value
        #expect(preview.tab.formatLabel == "Python" && preview.tab.isDirty)
        #expect(try await preview.value("document.querySelector('.code-language').textContent") as? String == "Python")
    }

    @Test func largeCodeFallsBackWithoutDroppingTextAndPlainTextStaysEditable() async throws {
        let source = "let name = \"Luma\"\n" + String(repeating: "// 长文件\n", count: 16000)
        let preview = try await render(source)
        defer { preview.close() }
        #expect(preview.state.metrics["highlighted"] == 0)
        #expect(try await preview.value("document.querySelector('pre code').textContent") as? String == source)
        #expect(preview.tab.hasPreview && preview.tab.canEdit)
        let plain = DocumentTab(url: URL(fileURLWithPath: "/tmp/note.txt"))
        #expect(plain.codeLanguage == nil && !plain.hasPreview)
        let json = DocumentTab(url: URL(fileURLWithPath: "/tmp/note.json"))
        #expect(json.codeLanguage?.identifier == "json" && json.hasPreview)
        #expect(CodeLanguage(url: URL(fileURLWithPath: "/tmp/NOTE.SWIFT"))?.title == "Swift")
    }
    @Test func documentViewOpensPythonPreviewAndKeepsEditingUndoAndSave() async throws {
        _ = NSApplication.shared
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let domain = "local.luma.code-ui.\(UUID().uuidString)"
        let preferences = try #require(UserDefaults(suiteName: domain))
        defer { try? FileManager.default.removeItem(at: directory); preferences.removePersistentDomain(forName: domain) }
        let file = directory.appendingPathComponent("note.py")
        let source = "def greet():\n    return \"Luma\"\n"
        try source.write(to: file, atomically: true, encoding: .utf8)
        let workspace = Workspace(preferences: preferences)
        workspace.open([file])
        let tab = try #require(workspace.activeTab)
        await tab.loadTask?.value
        let controller = NSHostingController(rootView: DocumentView(tab: tab, workspace: workspace).frame(width: 900, height: 650))
        let window = NSWindow(contentViewController: controller)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        func webView(in view: NSView) -> WKWebView? {
            if let web = view as? WKWebView { return web }
            return view.subviews.lazy.compactMap { webView(in: $0) }.first
        }
        func previewText() async throws -> String? {
            let deadline = ContinuousClock.now + .seconds(15)
            while ContinuousClock.now < deadline {
                controller.view.layoutSubtreeIfNeeded()
                if let web = webView(in: controller.view),
                   let text = try? await web.evaluateJavaScript("document.querySelector('pre code')?.textContent") as? String { return text }
                try await Task.sleep(for: .milliseconds(20))
            }
            return nil
        }
        #expect(try await previewText() == source)
        #expect(tab.editor == nil, "Code files should initially show a read-only preview")
        tab.showSource = true
        let deadline = ContinuousClock.now + .seconds(5)
        while tab.editor == nil && ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(20)) }
        let editor = try #require(tab.editor)
        controller.view.layoutSubtreeIfNeeded()
        editor.textView.setSelectedRange(NSRange(location: (source as NSString).length, length: 0))
        editor.textView.insertText("# edited\n", replacementRange: editor.textView.selectedRange())
        editor.textView.breakUndoCoalescing()
        #expect(tab.isDirty && tab.canUndo)
        tab.showSource = false
        #expect(try await previewText() == source + "# edited\n")
        #expect(tab.canUndo, "Undo after removing editor from the window")
        #expect(await workspace.save(tab))
        #expect(tab.canUndo, "Undo after saving from preview")
        #expect(try String(contentsOf: file, encoding: .utf8) == source + "# edited\n")
        tab.showSource = true
        #expect(tab.sourceEditor() === editor)
        #expect(tab.canUndo, "Undo after returning to source")
        #expect(!tab.isDirty)
    }

}
