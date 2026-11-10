import AppKit
import SwiftUI
import Testing
import ReaderCore
@testable import Luma

@MainActor @Suite(.serialized) struct ValueInspectorTests {
    @Test func replacementTargetsUTF16SelectionAndUsesNativeUndo() throws {
        _ = NSApplication.shared
        let text = "🙂 color = \"#3A6095\"; untouched = 42"
        let tab = DocumentTab(url: URL(fileURLWithPath: "/tmp/value.swift"))
        tab.draft = text; tab.savedText = text
        let editor = tab.sourceEditor()
        editor.textView.setSelectedRange((text as NSString).range(of: "\"#3A6095\""))
        let selection = try #require(editor.selectedValue())
        #expect(editor.replaceValue(selection, with: "\"#FFFFFF\""))
        #expect(tab.draft == "🙂 color = \"#FFFFFF\"; untouched = 42" && tab.isDirty && tab.canUndo)
        editor.textView.undoManager?.undo()
        #expect(tab.draft == text && !tab.isDirty)
        editor.textView.undoManager?.redo()
        #expect(tab.draft?.contains("#FFFFFF") == true)
    }
    @Test func refusesStaleSelectionAfterEditingOrReload() throws {
        let tab = DocumentTab(url: URL(fileURLWithPath: "/tmp/value.txt"))
        tab.draft = "1024"; tab.savedText = "1024"
        let editor = tab.sourceEditor()
        editor.textView.setSelectedRange(NSRange(location: 0, length: 4))
        let selection = try #require(editor.selectedValue())
        editor.textView.setSelectedRange(NSRange(location: 1, length: 1))
        #expect(!editor.replaceValue(selection, with: "2048"))
        editor.textView.setSelectedRange(selection.range)
        editor.textView.insertText("!", replacementRange: NSRange(location: 4, length: 0))
        #expect(!editor.replaceValue(selection, with: "2048"))
        #expect(tab.draft == "1024!")
        editor.textView.setSelectedRange(NSRange(location: 0, length: 0))
        #expect(editor.selectedValue() == nil)
    }
    @Test func inspectorFitsItsDeclaredWidth() throws {
        _ = NSApplication.shared
        let tab = DocumentTab(url: URL(fileURLWithPath: "/tmp/inspector.json"))
        tab.draft = "\"#3A6095\""; tab.savedText = tab.draft
        let selection = SourceValueSelection(range: NSRange(location: 0, length: 9), revision: 0, source: "\"#3A6095\"")
        let host = NSHostingView(rootView: ValueInspector(selection: selection, tab: tab, close: {}))
        let size = host.fittingSize
        #expect(size.width <= 380 && size.height > 150)
        host.frame = NSRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.appearance = NSAppearance(named: .aqua); window.contentView = host
        defer { window.contentView = nil; window.close() }
        host.layoutSubtreeIfNeeded()
        if let path = ProcessInfo.processInfo.environment["LUMA_CODE_PREVIEW_DIR"],
           let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) {
            host.cacheDisplay(in: host.bounds, to: bitmap)
            let data = try #require(bitmap.representation(using: .png, properties: [:]))
            let directory = URL(fileURLWithPath: path)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try data.write(to: directory.appendingPathComponent("value-inspector.png"))
        }
    }

}
