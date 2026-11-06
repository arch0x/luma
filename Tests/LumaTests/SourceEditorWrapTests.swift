import AppKit
import Testing
@testable import Luma

@MainActor @Suite(.serialized) struct SourceEditorWrapTests {
    @Test(arguments: ["token", "url", "chinese", "spaces", "tabs"])
    func editingWrapsLongLinesAtViewportWidthAndPreservesUndo(sample: String) async throws {
        let source: String = switch sample {
        case "token": String(repeating: "abcdef0123456789", count: 100)
        case "url": "https://example.com/" + String(repeating: "long-path/", count: 160)
        case "chinese": String(repeating: "中文自动换行🙂", count: 160)
        case "spaces": String(repeating: " ", count: 160) + String(repeating: "indented ", count: 160)
        default: String(repeating: "\t", count: 40) + String(repeating: "tabbed ", count: 160)
        }
        _ = NSApplication.shared
        let tab = DocumentTab(url: URL(fileURLWithPath: "/tmp/wrap.txt"))
        tab.draft = source; tab.savedText = source
        let editor = tab.sourceEditor()
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 700, height: 480), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = editor.scrollView
        defer { window.contentView = nil; window.close() }
        editor.textView.insertText("!", replacementRange: NSRange(location: (source as NSString).length, length: 0))
        editor.textView.breakUndoCoalescing()
        let selection = NSRange(location: 3, length: 5)
        editor.textView.setSelectedRange(selection)
        var heights: [CGFloat] = []
        for width: CGFloat in [700, 360, 560] {
            window.setContentSize(NSSize(width: width, height: 480))
            editor.scrollView.layoutSubtreeIfNeeded()
            editor.scrollView.tile()
            try await Task.sleep(for: .milliseconds(30))
            let container = try #require(editor.textView.textContainer)
            let layout = try #require(editor.textView.layoutManager)
            layout.ensureLayout(for: container)
            var lines = 0
            var rightEdge: CGFloat = 0
            layout.enumerateLineFragments(forGlyphRange: NSRange(location: 0, length: layout.numberOfGlyphs)) { _, used, _, _, _ in
                lines += 1
                rightEdge = max(rightEdge, used.maxX)
            }
            #expect(lines > 1)
            #expect(rightEdge <= container.containerSize.width + 1)
            #expect(editor.textView.frame.width <= editor.scrollView.contentView.bounds.width + 1)
            #expect(!editor.scrollView.hasHorizontalScroller)
            heights.append(layout.usedRect(for: container).height)
            #expect(editor.textView.selectedRange() == selection)
            editor.textView.scrollRangeToVisible(NSRange(location: (source as NSString).length, length: 0))
            #expect(abs(editor.scrollView.contentView.bounds.minX) < 1)
            #expect(editor.textView.string == source + "!")
            #expect(tab.draft == source + "!" && tab.canUndo)
        }
        #expect(heights[1] > heights[0])
        #expect(heights[2] < heights[1])
        editor.textView.undoManager?.undo()
        #expect(tab.draft == source && !tab.isDirty)
    }
}
