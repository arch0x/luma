import AppKit
import SwiftUI
import Testing
@testable import Luma

@MainActor @Suite(.serialized) struct EditorTypographyTests {
    @Test func fontSizePersistsAndInvalidSavedValuesUseDefault() throws {
        let domain = "local.luma.editor-font.\(UUID().uuidString)"
        let preferences = try #require(UserDefaults(suiteName: domain))
        defer { preferences.removePersistentDomain(forName: domain) }
        let workspace = Workspace(preferences: preferences)
        #expect(workspace.editorFontSize == 13)
        workspace.editorFontSize = 22
        #expect(Workspace(preferences: preferences).editorFontSize == 22)
        for invalid in [0.0, -5, 100, .infinity, .nan] {
            preferences.set(invalid, forKey: "editorFontSize")
            #expect(Workspace(preferences: preferences).editorFontSize == 13)
        }
        preferences.set("invalid", forKey: "editorFontSize")
        #expect(Workspace(preferences: preferences).editorFontSize == 13)
    }

    @Test func liveFontChangesReachActiveInactiveAndNewEditorsWithoutChangingDraftOrUndo() async throws {
        _ = NSApplication.shared
        let domain = "local.luma.editor-font-live.\(UUID().uuidString)"
        let preferences = try #require(UserDefaults(suiteName: domain))
        defer { preferences.removePersistentDomain(forName: domain) }
        let workspace = Workspace(preferences: preferences)
        let source = String(repeating: "编辑字号改变后继续自动换行。", count: 30)
        func tab(_ name: String) -> DocumentTab {
            let tab = DocumentTab(url: URL(fileURLWithPath: "/tmp/\(name).txt"))
            tab.draft = source; tab.savedText = source
            tab.applyPreview(.text(source))
            return tab
        }
        let first = tab("font-first"), second = tab("font-second")
        workspace.tabs = [first, second]; workspace.activeID = first.id
        let inactive = second.sourceEditor()
        let controller = NSHostingController(rootView: DocumentView(tab: first, workspace: workspace).frame(width: 700, height: 500))
        let window = NSWindow(contentViewController: controller)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        controller.view.layoutSubtreeIfNeeded()
        let editor = first.sourceEditor()
        editor.textView.insertText("!", replacementRange: NSRange(location: (source as NSString).length, length: 0))
        editor.textView.breakUndoCoalescing()
        let selection = NSRange(location: 1, length: 3)
        editor.textView.setSelectedRange(selection)
        let undoManager = editor.textView.undoManager
        var heights: [CGFloat] = []
        for size in [10.0, 20, 28] {
            workspace.editorFontSize = size
            let deadline = ContinuousClock.now + .seconds(2)
            while editor.textView.font?.pointSize != CGFloat(size) && ContinuousClock.now < deadline {
                try await Task.sleep(for: .milliseconds(20))
            }
            controller.view.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(30))
            #expect(editor.textView.font?.pointSize == CGFloat(size))
            #expect(inactive.textView.font?.pointSize == CGFloat(size))
            #expect((editor.textView.typingAttributes[.font] as? NSFont)?.pointSize == CGFloat(size))
            #expect(editor.textView.selectedRange() == selection)
            #expect(editor.textView.undoManager === undoManager && first.canUndo)
            #expect(first.draft == source + "!" && first.isDirty && first.savedText == source)
            #expect(second.draft == source && !second.isDirty)
            let container = try #require(editor.textView.textContainer)
            let layout = try #require(editor.textView.layoutManager)
            layout.ensureLayout(for: container)
            heights.append(layout.usedRect(for: container).height)
            #expect(editor.textView.frame.width <= editor.scrollView.contentView.bounds.width + 1)
            #expect(abs(editor.scrollView.contentView.bounds.minX) < 1)
        }
        #expect(heights[1] > heights[0] && heights[2] > heights[1])
        workspace.undo()
        #expect(first.draft == source && !first.isDirty)
        workspace.redo()
        #expect(first.draft == source + "!" && first.isDirty)
        workspace.editorFontSize = 22
        let third = tab("font-third")
        workspace.tabs.append(third); workspace.activeID = third.id
        controller.rootView = DocumentView(tab: third, workspace: workspace).frame(width: 700, height: 500)
        let deadline = ContinuousClock.now + .seconds(3)
        while third.editor?.textView.font?.pointSize != 22 && ContinuousClock.now < deadline {
            controller.view.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(third.editor?.textView.font?.pointSize == 22)
        #expect(!third.isDirty)
        #expect(Workspace(preferences: preferences).editorFontSize == 22)
        let newEditor = try #require(third.editor)
        newEditor.replaceFromDisk("重新载入后仍使用所选字号")
        #expect(newEditor.textView.font?.pointSize == 22)
    }
}
