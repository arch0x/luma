import AppKit
import PDFKit
import SwiftUI
import Testing
@testable import Luma

@MainActor @Suite(.serialized) struct SearchFocusTests {
    private func field(in view: NSView, placeholder: String) -> SearchTextField.Field? {
        if let field = view as? SearchTextField.Field, field.placeholderString == placeholder { return field }
        return view.subviews.lazy.compactMap { field(in: $0, placeholder: placeholder) }.first
    }

    private func focusedField(in host: NSView, window: NSWindow, placeholder: String) async throws -> SearchTextField.Field {
        let deadline = ContinuousClock.now + .seconds(3)
        while ContinuousClock.now < deadline {
            host.layoutSubtreeIfNeeded()
            if let field = field(in: host, placeholder: placeholder), let editor = field.currentEditor(),
               window.firstResponder === editor { return field }
            try await Task.sleep(for: .milliseconds(10))
        }
        Issue.record("Search field never became the window's first responder: \(placeholder)")
        throw URLError(.timedOut)
    }

    @Test(arguments: ["markdown", "source", "pdf"])
    func openingAndReactivatingFindPlacesCaretInSearchField(mode: String) async throws {
        _ = NSApplication.shared
        let domain = "local.luma.search-focus.\(UUID().uuidString)"
        let preferences = try #require(UserDefaults(suiteName: domain))
        defer { preferences.removePersistentDomain(forName: domain) }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let workspace = chineseWorkspace(preferences: preferences)
        let tab = DocumentTab(url: directory.appendingPathComponent(mode == "pdf" ? "note.pdf" : "note.md"))
        if mode == "pdf" {
            let document = PDFDocument()
            let page = PDFPage()
            page.setBounds(NSRect(x: 0, y: 0, width: 300, height: 400), for: .mediaBox)
            document.insert(page, at: 0)
            try #require(document.write(to: tab.url))
            tab.state = .ready(.native)
        } else {
            tab.draft = "# 正文\n\n可以查找的内容。"
            tab.savedText = tab.draft
            tab.state = .ready(.markdown(tab.draft ?? ""))
            tab.showSource = mode == "source"
        }
        workspace.tabs = [tab]
        workspace.activeID = tab.id
        workspace.openFind()
        let host = NSHostingView(rootView: DocumentView(tab: tab, workspace: workspace))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 500),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        defer { window.contentView = nil; window.close() }
        let placeholder = mode == "markdown" ? "在 Markdown 正文中查找" : mode == "pdf" ? "在 PDF 中查找" : "在源码中查找"
        let search = try await focusedField(in: host, window: window, placeholder: placeholder)
        let editor = try #require(search.currentEditor() as? NSTextView)
        editor.insertText("搜索词", replacementRange: editor.selectedRange())
        try await Task.sleep(for: .milliseconds(100))
        #expect(mode == "markdown" ? tab.markdownFind.query == "搜索词" : tab.sourceQuery == "搜索词")
        #expect(window.firstResponder === search.currentEditor())

        window.makeFirstResponder(nil)
        workspace.openFind()
        let reactivated = try await focusedField(in: host, window: window, placeholder: placeholder)
        let caret = try #require(reactivated.currentEditor() as? NSTextView).selectedRange()
        #expect(caret == NSRange(location: 3, length: 0))
        #expect(tab.showSource == (mode == "source"))
    }

    @Test func filenameFindReceivesFocusOnlyOnActivationAndCanBeReactivated() async throws {
        _ = NSApplication.shared
        let domain = "local.luma.library-focus.\(UUID().uuidString)"
        let preferences = try #require(UserDefaults(suiteName: domain))
        defer { preferences.removePersistentDomain(forName: domain) }
        let workspace = chineseWorkspace(preferences: preferences)
        let host = NSHostingView(rootView: WorkspaceView(workspace: workspace))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1000, height: 600),
                              styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        defer { window.delegate = nil; window.contentView = nil; window.close() }
        host.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(50))
        let initial = try #require(field(in: host, placeholder: "搜索文件名"))
        #expect(initial.currentEditor() == nil)
        workspace.libraryFindFocusRequest += 1
        let search = try await focusedField(in: host, window: window, placeholder: "搜索文件名")
        let editor = try #require(search.currentEditor() as? NSTextView)
        editor.insertText("笔记", replacementRange: editor.selectedRange())
        try await Task.sleep(for: .milliseconds(20))
        #expect(workspace.query == "笔记")
        window.makeFirstResponder(nil)
        workspace.libraryFindFocusRequest += 1
        let reactivated = try await focusedField(in: host, window: window, placeholder: "搜索文件名")
        #expect((reactivated.currentEditor() as? NSTextView)?.selectedRange() == NSRange(location: 2, length: 0))
        workspace.query = ""
        workspace.libraryFindFocusRequest += 1
        let deadline = ContinuousClock.now + .seconds(2)
        while ((reactivated.currentEditor() as? NSTextView)?.string != "" || reactivated.stringValue != "") && ContinuousClock.now < deadline {
            host.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect((reactivated.currentEditor() as? NSTextView)?.string == "")
        #expect(window.firstResponder === reactivated.currentEditor())
    }
}
