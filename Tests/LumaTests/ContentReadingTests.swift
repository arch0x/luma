import AppKit
import WebKit
import Testing
@testable import Luma

@MainActor @Suite(.serialized) struct ContentReadingTests {
    private func render(_ source: String, name: String = "reading.md", width: CGFloat = 520) async throws -> CodePreviewTests.Preview {
        _ = NSApplication.shared
        let tab = DocumentTab(url: URL(fileURLWithPath: "/tmp/\(name)"))
        tab.draft = source; tab.savedText = source
        let state = MarkdownRenderState()
        let coordinator = MarkdownWebView.Coordinator(source: source, tab: tab, previewWidth: 400, dark: false, state: state, onOpen: { _ in })
        let view = MarkdownWebView.makeWebView(coordinator: coordinator)
        view.frame = NSRect(x: 0, y: 0, width: width, height: 650)
        let preview = CodePreviewTests.Preview(view: view, coordinator: coordinator, state: state)
        let deadline = ContinuousClock.now + .seconds(20)
        while state.loading && ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(25)) }
        if state.loading || state.error != nil { preview.close(); throw CocoaError(.fileReadUnknown) }
        return preview
    }
    @Test func expandingTableAndCellPreservesOriginalDOMAndReadingPosition() async throws {
        let preview = try await render("# 标题\n\n| A | B |\n| --- | --- |\n| **全文** | <script>never()</script> |\n\n" + String(repeating: "正文\n\n", count: 30))
        defer { preview.close() }
        let before = try await preview.value("document.querySelector('main').innerHTML") as? String
        let y = try await preview.value("window.scrollY") as? Double
        #expect(try await preview.value("document.querySelector('.table-scroll .content-tools button').click(); document.querySelector('dialog').open") as? Bool == true)
        #expect(try await preview.value("document.querySelector('dialog').getBoundingClientRect().width > 450") as? Bool == true)
        #expect(try await preview.value("document.querySelector('dialog td strong').textContent") as? String == "全文")
        #expect(try await preview.value("document.querySelectorAll('dialog script').length") as? Int == 0)
        try await preview.snapshot("reading-expanded-table")
        _ = try await preview.value("window.luma.closeExpandedContent()")
        #expect(try await preview.value("document.querySelector('main').innerHTML") as? String == before)
        #expect(try await preview.value("window.scrollY") as? Double == y)
        #expect(try await preview.value("document.querySelector('td').dispatchEvent(new KeyboardEvent('keydown', {key:'Enter', bubbles:true})); document.querySelector('dialog .full-cell').textContent") as? String == "全文")
        _ = try await preview.value("window.luma.closeExpandedContent()")
    }
    @Test func fencedCodeHasOnlyCopyAndKeepsItsOriginalLongLine() async throws {
        let line = String(repeating: "abcdef", count: 80)
        let preview = try await render("```swift\n" + line + "\n```\n", width: 420)
        defer { preview.close() }
        #expect(try await preview.value("[...document.querySelectorAll('.code-toolbar button')].map(b=>b.textContent)") as? [String] == ["复制代码"])
        #expect(try await preview.value("getComputedStyle(document.querySelector('pre')).whiteSpace") as? String == "pre")
        #expect(try await preview.value("document.querySelector('pre').scrollWidth > document.querySelector('pre').clientWidth") as? Bool == true)
        #expect(try await preview.value("document.querySelector('pre code').textContent") as? String == line)
        #expect(try await preview.value("window.luma.expandContent === undefined") as? Bool == true)
        #expect(!preview.tab.isDirty)
    }
    @Test(arguments: ["json", "jsonl", "swift"])
    func standaloneCodeKeepsDefaultLayoutWithoutReadingControls(ext: String) async throws {
        let value = String(repeating: "x", count: 300)
        let raw = ext == "swift" ? "let value = \"" + value + "\"" : "{\"long\":\"" + value + "\"}"
        let preview = try await render(raw, name: "data." + ext, width: 420)
        defer { preview.close() }
        #expect(try await preview.value("document.querySelectorAll('.preview-controls,button[aria-pressed]').length") as? Int == 0)
        #expect(try await preview.value("[...document.querySelectorAll('button')].every(b=>b.textContent === '复制代码')") as? Bool == true)
        let whitespace = try await preview.value("getComputedStyle(document.querySelector('pre')).whiteSpace") as? String
        #expect(whitespace == (ext == "swift" ? "pre" : "pre-wrap"))
        #expect(try await preview.value("document.querySelector('pre code').textContent.includes('" + value + "')") as? Bool == true)
        #expect(preview.tab.draft == raw && !preview.tab.isDirty)
    }
    @Test func diagramCanBeReadAtNaturalSizeThenFitWithoutDuplicatingIDs() async throws {
        let preview = try await render("```mermaid\nflowchart LR\n A[开始阅读] --> B[查看文件] --> C[编辑源码] --> D[保存到磁盘]\n```", width: 420)
        defer { preview.close() }
        _ = try await preview.value("document.querySelector('.diagram-toolbar button:last-child').click()")
        #expect(try await preview.value("document.querySelector('dialog svg') !== null") as? Bool == true)
        #expect(try await preview.value("new Set([...document.querySelectorAll('[id]')].map(n=>n.id)).size === document.querySelectorAll('[id]').length") as? Bool == true)
        #expect(try await preview.value("document.querySelector('dialog .reading-scale').textContent") as? String == "100%")
        try await preview.snapshot("reading-expanded-diagram")
        _ = try await preview.value("[...document.querySelectorAll('dialog button')].find(b=>b.textContent==='适合窗口').click()")
        #expect(try await preview.value("parseInt(document.querySelector('dialog .reading-scale').textContent) <= 100") as? Bool == true)
        _ = try await preview.value("window.luma.closeExpandedContent()")
        #expect(try await preview.value("document.querySelectorAll('main .diagram-canvas svg').length") as? Int == 1)
    }


}
