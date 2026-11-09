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
        ("yaml", "YAML", "name: Luma\nenabled: true\n"),
        ("vue", "Vue", "<template><h1>{{ title }}</h1></template>\n"),
        ("svelte", "Svelte", "<h1>{title}</h1>\n"),
        ("less", "Less", "@color: blue;\nh1 { color: @color; }\n"),
        ("patch", "Diff", "@@ -1 +1 @@\n-old\n+new\n"),
        ("mjs", "JavaScript", "export const value = 42;\n"),
        ("graphql", "GraphQL", "query Notes { notes { title } }\n")
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

    @Test(arguments: ["vue", "svelte"])
    func componentPreviewHighlightsTypeScriptStylesAndTemplateExpressions(ext: String) async throws {
        let template = ext == "vue" ? "<h1>{{ value.title }}</h1>" : "{#if value}<h1>{value.title}</h1>{:else}<p>Empty</p>{/if}"
        let source = """
        <script lang="ts">
          interface Note { title: string }
          const value: Note = {title: "Luma"};
        </script>
        \(template)
        <style lang="less">
          @accent: blue;
          h1 { color: @accent; }
        </style>
        """
        let preview = try await render(source, name: "card.\(ext)")
        defer { preview.close() }
        #expect(try await preview.value("document.querySelector('pre code').textContent") as? String == source)
        #expect(try await preview.value("document.querySelector('.language-typescript .hljs-keyword')?.textContent") as? String == "interface")
        #expect(try await preview.value("document.querySelector('.language-less') !== null") as? Bool == true)
        #expect(try await preview.value("document.querySelector('.language-javascript .hljs-property')?.textContent") as? String == "title")
        if ext == "svelte" {
            #expect(try await preview.value("document.querySelector('.hljs-meta')?.textContent") as? String == "#if")
        }
        #expect(try await preview.value("document.querySelectorAll('main script, main style, main h1').length") as? Int == 0)
        #expect(preview.tab.hasPreview && preview.tab.draft == source)
        try await preview.snapshot("component-" + ext)
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
    @Test(arguments: ["py", "dockerfile", "mk", "dockerignore", "env", "gitignore"])
    func documentViewOpensCodePreviewAndKeepsEditingUndoAndSave(ext: String) async throws {
        _ = NSApplication.shared
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let domain = "local.luma.code-ui.\(UUID().uuidString)"
        let preferences = try #require(UserDefaults(suiteName: domain))
        defer { try? FileManager.default.removeItem(at: directory); preferences.removePersistentDomain(forName: domain) }
        let file = directory.appendingPathComponent("note.\(ext)")
        let source: String
        switch ext {
        case "py": source = "def greet():\n    return \"Luma\"\n"
        case "mk": source = "TITLE := Luma\nlist:\n\t@echo $(TITLE)\n"
        case "dockerignore": source = "# Context\n.build/\n*.log\n!README.md\n"
        case "gitignore": source = "# Local files\n*.log\n!README.md\n"
        case "env": source = "WORKSPACE=Luma\nMESSAGE=\"hello # world\"\n"
        default: source = "FROM scratch\nLABEL name=\"Luma\"\n"
        }
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

    @Test(arguments: ["Dockerfile", "dockerfile", "Dockerfile.dev", "Dockerfile.prod", "build.Dockerfile"])
    func dockerfilesHighlightInstructionsCommentsVariablesAndHeredocsWithoutExecution(name: String) async throws {
        let source = #"""
        # syntax=docker/dockerfile:1
        # 本地配置
        ARG BASE=alpine
        FROM ${BASE} AS build
        RUN echo "<script>window.executed=true</script>" \
          && echo ready
        COPY --from=build /data /data
        RUN <<EOF
        FROM literal heredoc text
        EOF
        CMD ["echo", "Luma"]
        """#
        let preview = try await render(source, name: name)
        defer { preview.close() }
        #expect(preview.tab.codeLanguage?.identifier == "dockerfile" && preview.tab.formatLabel == "Dockerfile")
        #expect(preview.tab.hasPreview && !preview.tab.showSource && !preview.tab.isDirty)
        #expect(try await preview.value("document.querySelector('pre code').textContent") as? String == source)
        let keywords = try #require(try await preview.value("[...document.querySelectorAll('.hljs-keyword')].map(node => node.textContent.trim())") as? [String])
        #expect(keywords.contains("FROM") && keywords.contains("COPY") && keywords.contains("CMD"))
        #expect(try await preview.value("document.querySelector('.hljs-variable')?.textContent") as? String == "${BASE}")
        #expect(try await preview.value("document.querySelector('.hljs-meta')?.textContent.includes('syntax=')") as? Bool == true)
        #expect(try await preview.value("[...document.querySelectorAll('.hljs-string')].some(node => node.textContent.includes('FROM literal heredoc text'))") as? Bool == true)
        #expect(try await preview.value("document.querySelectorAll('main script, main img').length") as? Int == 0)
        #expect(try await preview.value("window.executed === undefined") as? Bool == true)
        if name == "Dockerfile" { try await preview.snapshot("dockerfile-preview") }
    }

    @Test(arguments: ["Makefile", "GNUmakefile", "Makefile.dev", "build.mk"])
    func makefilesHighlightAndKeepRecipeTabs(name: String) async throws {
        let source = "# 本地任务\nTITLE := Luma\n.PHONY: list\nlist:\n\t@echo $(TITLE)\n"
        let preview = try await render(source, name: name)
        defer { preview.close() }
        #expect(preview.tab.codeLanguage?.identifier == "makefile" && preview.tab.hasPreview)
        #expect(try await preview.value("document.querySelector('pre code').textContent") as? String == source)
        #expect(try await preview.value("document.querySelectorAll('pre code span').length > 0") as? Bool == true)
        #expect(preview.tab.formatLabel == "Makefile" && !preview.tab.isDirty)
        if name == "Makefile" { try await preview.snapshot("makefile-preview") }
    }

    @Test(arguments: [".dockerignore", "Dockerfile.dockerignore", "build.Dockerfile.dockerignore"])
    func dockerignoreHighlightsRulesInsteadOfDockerInstructions(name: String) async throws {
        let source = "# Context\n**/*.log\n!README.md\ncache?/\nfile[0-9].tmp\ndata#literal\n<script>window.executed=true</script>\n"
        let preview = try await render(source, name: name)
        defer { preview.close() }
        #expect(preview.tab.codeLanguage?.identifier == "dockerignore" && preview.tab.hasPreview)
        #expect(preview.tab.formatLabel == ".dockerignore")
        #expect(try await preview.value("document.querySelector('pre code').textContent") as? String == source)
        #expect(try await preview.value("document.querySelector('.hljs-comment')?.textContent") as? String == "# Context")
        #expect(try await preview.value("document.querySelector('.hljs-keyword')?.textContent") as? String == "!")
        #expect(try await preview.value("document.querySelectorAll('.hljs-symbol').length >= 4") as? Bool == true)
        #expect(try await preview.value("document.querySelectorAll('main script, main img').length") as? Int == 0)
        #expect(try await preview.value("window.executed === undefined") as? Bool == true)
        if name == ".dockerignore" { try await preview.snapshot("dockerignore-preview") }
    }

    @Test(arguments: [".gitignore", "global.gitignore"])
    func gitignoreHighlightsEscapedPatternsWithoutChangingRules(name: String) async throws {
        let source = "# Local files\n**/*.log\n!README.md\n\\#literal\n\\!literal\ncache?/\nfile[0-9].tmp\ndata#literal\n"
        let preview = try await render(source, name: name)
        defer { preview.close() }
        #expect(preview.tab.codeLanguage?.identifier == "gitignore" && preview.tab.hasPreview)
        #expect(try await preview.value("document.querySelector('pre code').textContent") as? String == source)
        #expect(try await preview.value("document.querySelectorAll('.hljs-comment').length") as? Int == 1)
        #expect(try await preview.value("document.querySelectorAll('.hljs-keyword').length") as? Int == 1)
        #expect(try await preview.value("document.querySelectorAll('.hljs-literal').length") as? Int == 2)
        #expect(try await preview.value("document.querySelectorAll('.hljs-symbol').length >= 4") as? Bool == true)
        if name == ".gitignore" { try await preview.snapshot("gitignore-preview") }
    }

    @Test(arguments: [".env", ".env.local", ".env.production", "workspace.env"])
    func dotenvHighlightsKeysQuotedHashesAndMultilineValues(name: String) async throws {
        let source = "# Public examples\nexport WORKSPACE=Luma\nWIDTH=840\nMESSAGE=\"hello # literal ${WORKSPACE}\"\nMULTILINE='first\nsecond'\nPLAIN=value # inline comment\nHTML=\"<script>window.executed=true</script>\"\n"
        let preview = try await render(source, name: name)
        defer { preview.close() }
        #expect(preview.tab.codeLanguage?.identifier == "dotenv" && preview.tab.hasPreview)
        #expect(preview.tab.formatLabel == ".env" && !preview.tab.isDirty)
        #expect(try await preview.value("document.querySelector('pre code').textContent") as? String == source)
        #expect(try await preview.value("document.querySelector('.hljs-attr')?.textContent") as? String == "WORKSPACE")
        #expect(try await preview.value("document.querySelectorAll('.hljs-comment').length") as? Int == 2)
        #expect(try await preview.value("[...document.querySelectorAll('.hljs-string')].some(node => node.textContent.includes('hello # literal'))") as? Bool == true)
        #expect(try await preview.value("[...document.querySelectorAll('.hljs-string')].some(node => node.textContent.includes('first\\nsecond'))") as? Bool == true)
        #expect(try await preview.value("getComputedStyle(document.querySelector('.hljs-attr')).color !== getComputedStyle(document.querySelector('.hljs-string')).color") as? Bool == true)
        #expect(try await preview.value("document.querySelectorAll('main script, main img').length") as? Int == 0)
        #expect(try await preview.value("window.executed === undefined") as? Bool == true)
        if name == ".env" { try await preview.snapshot("dotenv-preview") }
    }

}
