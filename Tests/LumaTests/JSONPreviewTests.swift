import AppKit
import SwiftUI
import WebKit
import Testing
@testable import Luma

@MainActor @Suite(.serialized) struct JSONPreviewTests {
    private func render(_ source: String, dark: Bool = false, name: String = "note.json", allowingError: Bool = false) async throws -> CodePreviewTests.Preview {
        _ = NSApplication.shared
        let tab = DocumentTab(url: URL(fileURLWithPath: "/tmp/\(name)"))
        tab.draft = source; tab.savedText = source
        let state = MarkdownRenderState()
        let coordinator = MarkdownWebView.Coordinator(source: source, tab: tab, dark: dark, state: state, onOpen: { _ in })
        let view = MarkdownWebView.makeWebView(coordinator: coordinator)
        view.frame = NSRect(x: 0, y: 0, width: 1000, height: 850)
        let preview = CodePreviewTests.Preview(view: view, coordinator: coordinator, state: state)
        let deadline = ContinuousClock.now + .seconds(20)
        while state.loading && ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(20)) }
        guard !state.loading && (allowingError || state.error == nil) else {
            preview.close()
            throw NSError(domain: "JSONPreviewTests", code: 1, userInfo: [NSLocalizedDescriptionKey: state.error ?? "Timed out"])
        }
        return preview
    }

    @Test(arguments: [false, true])
    func formattedPreviewHasLineNumbersAndDistinctTypeColors(dark: Bool) async throws {
        let raw = #"{"project":"Luma","files":42,"active":true,"optional":null,"details":{"description":"本地文件阅读器","tags":["Swift","Python"],"empty":[]}}"#
        let expected = """
        {
          "project": "Luma",
          "files": 42,
          "active": true,
          "optional": null,
          "details": {
            "description": "本地文件阅读器",
            "tags": [
              "Swift",
              "Python"
            ],
            "empty": []
          }
        }
        """
        let preview = try await render(raw, dark: dark)
        defer { preview.close() }
        #expect(try await preview.value("document.querySelector('pre code').textContent") as? String == expected)
        #expect(try await preview.value("document.querySelector('.json-line-numbers').textContent") as? String == (1...expected.components(separatedBy: "\n").count).map(String.init).joined(separator: "\n"))
        #expect(try await preview.value("document.querySelectorAll('.code-toolbar').length") as? Int == 0)
        let colors = try #require(try await preview.value("['attr','string','number','literal'].map(type => getComputedStyle(document.querySelector('.hljs-' + type)).color)") as? [String])
        #expect(Set(colors).count == 4)
        #expect(try await preview.value("document.querySelector('.json-line-numbers').getAttribute('aria-hidden')") as? String == "true")
        #expect(try await preview.value("getComputedStyle(document.querySelector('.json-line-numbers')).getPropertyValue('-webkit-user-select')") as? String == "none")
        #expect(preview.tab.draft == raw && !preview.tab.isDirty)
        try await preview.snapshot(dark ? "json-dark" : "json-light")
    }

    @Test func formattingPreservesKeyOrderNumberPrecisionEscapesAndDuplicateKeys() async throws {
        let raw = #"{"z":900719925474099312345,"a":-0,"tiny":1.2300e-40,"path":"a\/b","escaped":"\u4f60\n\"","same":1,"same":2,"html":"<script>window.executed=true</script>"}"#
        let expected = #"""
        {
          "z": 900719925474099312345,
          "a": -0,
          "tiny": 1.2300e-40,
          "path": "a\/b",
          "escaped": "\u4f60\n\"",
          "same": 1,
          "same": 2,
          "html": "<script>window.executed=true</script>"
        }
        """#
        let preview = try await render(raw)
        defer { preview.close() }
        #expect(try await preview.value("document.querySelector('pre code').textContent") as? String == expected)
        #expect(try await preview.value("document.querySelectorAll('main script, main img, main h1, main .katex').length") as? Int == 0)
        #expect(try await preview.value("window.executed === undefined") as? Bool == true)
        #expect(preview.tab.draft == raw && preview.tab.savedText == raw)
    }

    @Test(arguments: ["{}", "[]", "[1,true,null,\"str\"]", "\"hello\"", "42", "false", "null"])
    func arraysAndScalarJSONAreReadable(source: String) async throws {
        let preview = try await render(source, name: "note.geojson")
        defer { preview.close() }
        let text = try #require(try await preview.value("document.querySelector('pre code').textContent") as? String)
        #expect(!text.isEmpty && preview.tab.formatLabel == "JSON")
        #expect(try await preview.value("document.querySelector('main').hasAttribute('data-json-preview')") as? Bool == true)
        let equivalent = try await preview.view.callAsyncJavaScript("return JSON.stringify(JSON.parse(source)) === JSON.stringify(JSON.parse(document.querySelector('pre code').textContent));", arguments: ["source": source], in: nil, contentWorld: .page)
        #expect(equivalent as? Bool == true)
    }

    @Test func largeFormattingExpansionFallsBackWithoutTruncation() async throws {
        let source = String(repeating: "[", count: 80) + Array(repeating: "0", count: 16000).joined(separator: ",") + String(repeating: "]", count: 80)
        let preview = try await render(source)
        defer { preview.close() }
        #expect(try await preview.value("document.querySelector('pre code').textContent") as? String == source)
        #expect(preview.tab.draft == source && !preview.tab.isDirty)
    }

    @Test func JSONDocumentViewPreviewsDraftWithoutRewritingFileOrUndoHistory() async throws {
        _ = NSApplication.shared
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let domain = "local.luma.json-ui.\(UUID().uuidString)"
        let preferences = try #require(UserDefaults(suiteName: domain))
        defer { try? FileManager.default.removeItem(at: directory); preferences.removePersistentDomain(forName: domain) }
        let raw = #"{"z":1,"a":true}"#
        let edited = #"{"z":2,"a":false}"#
        let file = directory.appendingPathComponent("note.json")
        try raw.write(to: file, atomically: true, encoding: .utf8)
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
        func displayedText() async throws -> String? {
            let deadline = ContinuousClock.now + .seconds(15)
            while ContinuousClock.now < deadline {
                controller.view.layoutSubtreeIfNeeded()
                if let web = webView(in: controller.view),
                   let text = try? await web.evaluateJavaScript("document.querySelector('pre code')?.textContent") as? String { return text }
                try await Task.sleep(for: .milliseconds(20))
            }
            return nil
        }
        #expect(try await displayedText() == "{\n  \"z\": 1,\n  \"a\": true\n}")
        #expect(!tab.isDirty && tab.editor == nil)
        #expect(try String(contentsOf: file, encoding: .utf8) == raw)
        tab.showSource = true
        let deadline = ContinuousClock.now + .seconds(5)
        while tab.editor == nil && ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(20)) }
        let editor = try #require(tab.editor)
        editor.textView.insertText(edited, replacementRange: NSRange(location: 0, length: (raw as NSString).length))
        editor.textView.breakUndoCoalescing()
        await tab.previewTask?.value
        tab.showSource = false
        #expect(try await displayedText() == "{\n  \"z\": 2,\n  \"a\": false\n}")
        #expect(tab.isDirty && tab.canUndo && tab.draft == edited)
        #expect(try String(contentsOf: file, encoding: .utf8) == raw)
        #expect(await workspace.save(tab))
        #expect(try String(contentsOf: file, encoding: .utf8) == edited)
        #expect(tab.canUndo && !tab.isDirty)
        workspace.undo()
        await tab.previewTask?.value
        #expect(tab.draft == raw && tab.isDirty)
        tab.edit("{unfinished")
        await tab.previewTask?.value
        #expect(tab.previewError != nil && tab.canEdit && tab.draft == "{unfinished")
    }
    @Test(arguments: [false, true])
    func longStringsWrapAndLineNumbersStayAlignedAfterResize(dark: Bool) async throws {
        let long = String(repeating: "很长的内容 https://example.com/abcdef/", count: 20) + String(repeating: "x", count: 300)
        let raw = "{\"long\":\"" + long + "\",\"next\":1}"
        let expected = "{\n  \"long\": \"" + long + "\",\n  \"next\": 1\n}"
        let preview = try await render(raw, dark: dark)
        defer { preview.close() }
        let window = NSWindow(contentRect: preview.view.bounds, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = preview.view
        defer { window.contentView = nil; window.close() }
        var heights: [Double] = []
        for width in [700, 420] {
            window.setContentSize(NSSize(width: width, height: 850))
            preview.view.layoutSubtreeIfNeeded()
            let deadline = ContinuousClock.now + .seconds(2)
            while (try await preview.value("window.innerWidth") as? Int) != width && ContinuousClock.now < deadline {
                try await Task.sleep(for: .milliseconds(20))
            }
            let layoutDeadline = ContinuousClock.now + .seconds(3)
            while (try await preview.value("[...document.querySelectorAll('.json-code-line')].every((line, index) => Math.abs(line.getBoundingClientRect().top - document.querySelectorAll('.json-line-number')[index].getBoundingClientRect().top) < 1)") as? Bool) != true && ContinuousClock.now < layoutDeadline {
                try await Task.sleep(for: .milliseconds(20))
            }
            let layout = try #require(try await preview.value("""
                (() => {
                  const lines = [...document.querySelectorAll('.json-code-line')];
                  const numbers = [...document.querySelectorAll('.json-line-number')];
                  return {
                    height: lines[1].getBoundingClientRect().height,
                    lineHeight: parseFloat(getComputedStyle(lines[1]).lineHeight),
                    aligned: lines.every((line, index) => Math.abs(line.getBoundingClientRect().top - numbers[index].getBoundingClientRect().top) < 1),
                    fits: document.documentElement.scrollWidth <= window.innerWidth + 1
                  };
                })()
                """) as? [String: Any])
            let height = try #require(layout["height"] as? Double)
            let lineHeight = try #require(layout["lineHeight"] as? Double)
            heights.append(height)
            #expect(height > lineHeight * 2)
            #expect(layout["aligned"] as? Bool == true)
            #expect(layout["fits"] as? Bool == true)
            #expect(try await preview.value("document.querySelector('pre code').textContent") as? String == expected)
        }
        #expect(heights[1] > heights[0])
        #expect(try await preview.value("document.querySelector('.json-line-numbers').textContent") as? String == "1\n2\n3\n4")
        let selected = try await preview.value("""
            const range = document.createRange(); range.selectNodeContents(document.querySelector('pre code'));
            const selection = window.getSelection(); selection.removeAllRanges(); selection.addRange(range);
            const data = new DataTransfer();
            document.dispatchEvent(new ClipboardEvent('copy', {clipboardData: data, cancelable: true, bubbles: true}));
            data.getData('text/plain');
            """) as? String
        #expect(selected == expected, "Soft wrapping must not add copied newlines")
        #expect(preview.tab.draft == raw && !preview.tab.isDirty)
        try await preview.snapshot(dark ? "json-wrap-dark" : "json-wrap-light")
    }

    @Test(arguments: ["jsonl", "ndjson"])
    func JSONLinesFormatsEachRecordPreservesLexemesAndTracksOriginalLines(ext: String) async throws {
        let source = #"{"z":900719925474099312345,"a":-0,"path":"a\/b","same":1,"same":2}"# + "\r\n\r\n" + #"{"title":"本地阅读","active":true,"items":[1,2]}"# + "\r\n"
        let preview = try await render(source, name: "records.\(ext)")
        defer { preview.close() }
        let records = try #require(try await preview.value("[...document.querySelectorAll('pre code')].map(code => code.textContent)") as? [String])
        #expect(records.count == 2)
        #expect(records[0].contains("\n  \"z\": 900719925474099312345,"))
        #expect(records[0].contains(#""path": "a\/b""#) && records[0].contains("\"a\": -0"))
        #expect(records[0].components(separatedBy: "\"same\"").count == 3)
        #expect(records[1].contains("\"items\": [\n    1,\n    2\n  ]"))
        #expect(try await preview.value("[...document.querySelectorAll('.json-record-title')].map(node => node.textContent)") as? [String] == ["记录 1 · 源码第 1 行", "记录 2 · 源码第 3 行"])
        #expect(try await preview.value("document.querySelectorAll('.json-record-error').length") as? Int == 0)
        #expect(try await preview.value("document.querySelectorAll('.json-line-numbers').length") as? Int == 2)
        #expect(preview.tab.hasPreview && preview.tab.formatLabel == ext.uppercased())
        #expect(preview.tab.draft == source && !preview.tab.isDirty)
        try await preview.snapshot("preview-" + ext)
        let copied = try await preview.value("""
          const code = document.querySelectorAll('pre code')[1];
          const range = document.createRange(); range.selectNodeContents(code);
          const selection = window.getSelection(); selection.removeAllRanges(); selection.addRange(range);
          const data = new DataTransfer();
          document.dispatchEvent(new ClipboardEvent('copy', {clipboardData: data, cancelable: true, bubbles: true}));
          data.getData('text/plain');
          """) as? String
        #expect(copied == records[1], "Copying a later record must not use the first record or include its heading")
    }

    @Test func badJSONLineDoesNotHideOtherRecordsOrExecuteHTML() async throws {
        let source = #"{"id":1}"# + "\n{unfinished\n" + #"{"html":"<script>window.executed=true</script>"}"#
        let preview = try await render(source, dark: true, name: "records.jsonl")
        defer { preview.close() }
        #expect(try await preview.value("document.querySelectorAll('.json-record').length") as? Int == 3)
        #expect(try await preview.value("document.querySelectorAll('.json-record-error').length") as? Int == 1)
        #expect(try await preview.value("document.querySelector('.json-record-error').textContent.startsWith('第 2 行')") as? Bool == true)
        #expect(try await preview.value("document.querySelectorAll('pre code')[1].textContent") as? String == "{unfinished")
        #expect(try await preview.value("document.querySelectorAll('main script, main img, main iframe').length") as? Int == 0)
        #expect(try await preview.value("window.executed === undefined") as? Bool == true)
        #expect(preview.tab.canEdit && preview.tab.draft == source)
        try await preview.snapshot("jsonl-invalid-dark")
    }

    @Test func JSONLinesHandlesScalarsEmptyFilesAndRecordLimitWithoutTruncation() async throws {
        let scalars = try await render("false\nnull\n[1,2]\n\"hello\"\n", name: "values.ndjson")
        defer { scalars.close() }
        #expect(try await scalars.value("document.querySelectorAll('.json-record').length") as? Int == 4)
        let empty = try await render("\n \n", name: "empty.jsonl")
        defer { empty.close() }
        #expect(try await empty.value("document.querySelector('.json-preview-note').textContent") as? String == "没有可预览的记录。")
        let source = String(repeating: "{}\n", count: 10001)
        let large = try await render(source, name: "large.jsonl")
        defer { large.close() }
        #expect(try await large.value("document.querySelector('.json-preview-note').textContent.includes('10,000')") as? Bool == true)
        #expect(try await large.value("document.querySelector('pre code').textContent") as? String == source)
    }

    @Test(arguments: [false, true])
    func JSONCFormatsCommentsAndTrailingCommasWithoutRewritingThem(dark: Bool) async throws {
        let source = #"""
        // 阅读配置
        {"url":"https://example.com/a//b", /* 保留注释
        也保留这一行 */ "value":900719925474099312345,"escaped":"\u4f60\n","items":[1,2,],}
        """#
        let preview = try await render(source, dark: dark, name: "settings.jsonc")
        defer { preview.close() }
        let text = try #require(try await preview.value("document.querySelector('pre code').textContent") as? String)
        #expect(text.contains("// 阅读配置") && text.contains("/* 保留注释\n也保留这一行 */"))
        #expect(text.contains("\"url\": \"https://example.com/a//b\""))
        #expect(text.contains("900719925474099312345") && text.contains(#""escaped": "\u4f60\n""#))
        #expect(text.contains("1,\n    2,\n  ],\n}"))
        #expect(try await preview.value("[...document.querySelectorAll('.json-code-line .hljs-comment')].some(node => node.textContent.includes('也保留这一行'))") as? Bool == true)
        #expect(try await preview.value("window.lumaFormatJSONC(document.querySelector('pre code').textContent) === document.querySelector('pre code').textContent") as? Bool == true)
        #expect(preview.tab.formatLabel == "JSONC" && preview.tab.hasPreview && preview.tab.draft == source && !preview.tab.isDirty)
        try await preview.snapshot(dark ? "jsonc-dark" : "jsonc-light")
    }

    @Test(arguments: ["/* unfinished", "[// comment\n,]", "[1,,]", "{\"value\":,}", "{bad}"])
    func invalidJSONCKeepsSourceAndReportsAFormatError(source: String) async throws {
        let preview = try await render(source, name: "bad.jsonc", allowingError: true)
        defer { preview.close() }
        #expect(preview.state.error?.contains("JSONC 格式错误") == true)
        #expect(preview.tab.draft == source && preview.tab.canEdit)
    }

    @Test(arguments: ["jsonc", "jsonl", "ndjson"])
    func JSONVariantDocumentViewKeepsDraftUndoAndOriginalFileFormat(ext: String) async throws {
        _ = NSApplication.shared
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID()).\(ext)")
        let domain = "local.luma.json-variant-ui.\(UUID())"
        let preferences = try #require(UserDefaults(suiteName: domain))
        defer { try? FileManager.default.removeItem(at: file); preferences.removePersistentDomain(forName: domain) }
        let raw = ext == "jsonc" ? "// keep this comment\n{\"value\":1,}" : "{\"value\":1}\n{\"next\":true}\n"
        let changed = raw.replacingOccurrences(of: ":1", with: ":2")
        try Data(raw.utf8).write(to: file)
        let workspace = Workspace(preferences: preferences)
        workspace.open([file])
        let tab = try #require(workspace.activeTab)
        await tab.loadTask?.value
        let host = NSHostingController(rootView: DocumentView(tab: tab, workspace: workspace).frame(width: 900, height: 650))
        let window = NSWindow(contentViewController: host)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        func webView(in view: NSView) -> WKWebView? {
            if let web = view as? WKWebView { return web }
            return view.subviews.lazy.compactMap { webView(in: $0) }.first
        }
        func waitForValue(_ value: Int) async throws -> Bool {
            let deadline = ContinuousClock.now + .seconds(15)
            while ContinuousClock.now < deadline {
                host.view.layoutSubtreeIfNeeded()
                if let web = webView(in: host.view),
                   let text = try? await web.evaluateJavaScript("document.querySelector('pre code')?.textContent") as? String,
                   text.contains("\"value\": \(value)") { return true }
                try await Task.sleep(for: .milliseconds(20))
            }
            return false
        }
        #expect(try await waitForValue(1))
        #expect(tab.editor == nil && !tab.isDirty)
        tab.showSource = true
        let deadline = ContinuousClock.now + .seconds(5)
        while tab.editor == nil && ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(20)) }
        let editor = try #require(tab.editor)
        editor.textView.insertText(changed, replacementRange: NSRange(location: 0, length: (raw as NSString).length))
        editor.textView.breakUndoCoalescing()
        tab.showSource = false
        #expect(try await waitForValue(2))
        #expect(tab.canUndo && tab.isDirty && tab.draft == changed)
        #expect(try String(contentsOf: file, encoding: .utf8) == raw)
        #expect(await workspace.save(tab))
        #expect(try String(contentsOf: file, encoding: .utf8) == changed)
        #expect(tab.canUndo)
        workspace.undo()
        #expect(tab.draft == raw && tab.isDirty)
    }

}
