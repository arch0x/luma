import AppKit
import SwiftUI
import ReaderCore
import Testing
@testable import Luma

@MainActor @Suite(.serialized) struct DocumentReaderRailTests {
    private func buttons(in view: NSView) -> [DocumentRailNativeButton] {
        (view as? DocumentRailNativeButton).map { [$0] } ?? view.subviews.flatMap { buttons(in: $0) }
    }

    private func waitForButtons(in view: NSView) async throws -> [DocumentRailNativeButton] {
        let deadline = ContinuousClock.now + .seconds(5)
        while ContinuousClock.now < deadline {
            view.window?.displayIfNeeded()
            view.layoutSubtreeIfNeeded()
            let result = buttons(in: view)
            if result.count == 2 && view.bounds.width > 0 && view.bounds.height > 0 { return result }
            try await Task.sleep(for: .milliseconds(20))
        }
        throw URLError(.timedOut)
    }

    private func snapshot(_ view: NSView, name: String) throws {
        guard let path = ProcessInfo.processInfo.environment["LUMA_READER_RAIL_DIR"] else { return }
        view.layoutSubtreeIfNeeded()
        let bitmap = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: bitmap)
        let data = try #require(bitmap.representation(using: .png, properties: [:]))
        let folder = URL(fileURLWithPath: path)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try data.write(to: folder.appendingPathComponent(name + ".png"))
    }

    @Test func informationCountsCurrentGraphemesAndReportsActualEncoding() throws {
        let tab = DocumentTab(url: URL(fileURLWithPath: "/tmp/info.txt"))
        let source = "你👩🏽‍💻e\u{301}\r\n"
        tab.acceptDisk(try TextFileSnapshot(data: Data(("\u{FEFF}" + source).utf8)))
        let information = DocumentInformation(tab: tab)
        #expect(information.characterCount == 4)
        #expect(information.sourceByteCount == 22)
        #expect(information.encoding == "UTF-8（BOM）")
        tab.edit("新的草稿")
        #expect(DocumentInformation(tab: tab).characterCount == 4)
        #expect(DocumentInformation(tab: tab).sourceByteCount == 12)
        #expect(tab.isDirty)
        let pdf = DocumentInformation(tab: DocumentTab(url: URL(fileURLWithPath: "/tmp/file.pdf")))
        #expect(pdf.format == "PDF" && pdf.characterCount == nil && pdf.encoding == "不适用")
        let png = DocumentInformation(tab: DocumentTab(url: URL(fileURLWithPath: "/tmp/file.png")))
        #expect(png.format == "PNG 图片" && png.sourceByteCount == nil)
        let csv = DocumentInformation(tab: DocumentTab(url: URL(fileURLWithPath: "/tmp/file.tsv")))
        #expect(csv.format == "TSV" && csv.encoding == "未识别")
    }

    @Test(arguments: [false, true])
    func hoveringShowsAndHidesInformationWithoutMovingFocusOrChangingTheDraft(dark: Bool) async throws {
        _ = NSApplication.shared
        let domain = "local.luma.rail-hover.\(UUID())"
        let preferences = try #require(UserDefaults(suiteName: domain))
        defer { preferences.removePersistentDomain(forName: domain) }
        let workspace = chineseWorkspace(preferences: preferences)
        let tab = DocumentTab(url: URL(fileURLWithPath: "/tmp/元数据与草稿.txt"))
        tab.acceptDisk(try TextFileSnapshot(data: Data("本地阅读空间\n一份文档，一组数据。".utf8)))
        tab.applyPreview(.text(tab.draft ?? ""))
        let host = NSHostingController(rootView: DocumentView(tab: tab, workspace: workspace)
            .environment(\.colorScheme, dark ? .dark : .light).frame(width: 690, height: 500))
        let window = NSWindow(contentViewController: host)
        window.isReleasedWhenClosed = false
        window.setContentSize(NSSize(width: 690, height: 500))
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        defer { window.close() }
        let controls = try await waitForButtons(in: host.view)
        let info = try #require(controls.first { $0.identifier?.rawValue == "documentInformation" })
        let finder = try #require(controls.first { $0.identifier?.rawValue == "revealDocumentInFinder" })
        #expect(info.convert(info.bounds, to: nil).midY > finder.convert(finder.bounds, to: nil).midY)
        #expect(abs(info.convert(info.bounds, to: nil).midX - finder.convert(finder.bounds, to: nil).midX) < 1)
        let editor = try #require(tab.editor)
        #expect(window.makeFirstResponder(editor.textView))
        editor.textView.insertText("草稿：", replacementRange: NSRange(location: 0, length: 0))
        editor.textView.breakUndoCoalescing()
        editor.textView.setSelectedRange(NSRange(location: 1, length: 2))
        let draft = tab.draft
        let width = editor.scrollView.bounds.width
        info.updateTrackingAreas()
        #expect(info.trackingAreas.contains { $0.owner === info && $0.options.contains(.mouseEnteredAndExited) })
        let entered = try #require(NSEvent.enterExitEvent(with: .mouseEntered, location: .zero,
            modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil,
            eventNumber: 1, trackingNumber: 0, userData: nil))
        info.mouseEntered(with: entered)
        let deadline = ContinuousClock.now + .seconds(2)
        while !info.selected && ContinuousClock.now < deadline {
            host.view.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(info.selected)
        #expect(window.firstResponder === editor.textView)
        #expect(editor.scrollView.bounds.width == width)
        #expect(tab.draft == draft && tab.isDirty && tab.canUndo)
        #expect(editor.textView.selectedRange() == NSRange(location: 1, length: 2))
        try snapshot(host.view, name: dark ? "information-dark" : "information-light")
        let exited = try #require(NSEvent.enterExitEvent(with: .mouseExited, location: .zero,
            modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil,
            eventNumber: 2, trackingNumber: 0, userData: nil))
        info.mouseExited(with: exited)
        let closeDeadline = ContinuousClock.now + .seconds(2)
        while info.selected && ContinuousClock.now < closeDeadline {
            host.view.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(!info.selected && window.firstResponder === editor.textView)
        #expect(tab.draft == draft && editor.scrollView.bounds.width == width)
        try snapshot(host.view, name: dark ? "rail-dark" : "rail-light")
        info.performClick(nil)
        let keyboardDeadline = ContinuousClock.now + .seconds(2)
        while !info.selected && ContinuousClock.now < keyboardDeadline { try await Task.sleep(for: .milliseconds(20)) }
        #expect(info.selected, "The information must also be available through the button's keyboard action")
    }

    @Test(arguments: ["欢迎.md", "项目.json", "阅读空间.pdf", "留白.png", "图片资源/阅读 流程.svg", "阅读清单.csv", "__long_navigation__"])
    func everyReaderHasExactlyOnePairOfRailActions(path: String) async throws {
        _ = NSApplication.shared
        let domain = "local.luma.rail-readers.\(UUID())"
        let preferences = try #require(UserDefaults(suiteName: domain))
        defer { preferences.removePersistentDomain(forName: domain) }
        let workspace = chineseWorkspace(preferences: preferences)
        let samples = try #require(workspace.samplesURL)
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID()).md")
        defer { try? FileManager.default.removeItem(at: temporary) }
        if path == "__long_navigation__" {
            let source = (1...600).map { "# 章节 \($0)\n\n阅读段落。\n" }.joined(separator: "\n")
            try Data(source.utf8).write(to: temporary)
            workspace.open([temporary])
        } else { workspace.open([samples.appendingPathComponent(path)]) }
        let tab = try #require(workspace.activeTab)
        await tab.loadTask?.value
        let host = NSHostingController(rootView: DocumentView(tab: tab, workspace: workspace).frame(width: 900, height: 600))
        let window = NSWindow(contentViewController: host)
        window.isReleasedWhenClosed = false
        window.setContentSize(NSSize(width: 900, height: 600))
        defer { window.close() }
        let controls = try await waitForButtons(in: host.view)
        if path == "__long_navigation__" {
            let deadline = ContinuousClock.now + .seconds(15)
            while tab.markdownRenderState.loading && ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(20)) }
            #expect(tab.markdownRenderState.headings.count == 600)
            host.view.layoutSubtreeIfNeeded()
            try snapshot(host.view, name: "long-navigation")
        }
        if tab.kind != .markdown {
            let pair = controls.map { $0.convert($0.bounds, to: host.view) }.reduce(NSRect.null) { $0.union($1) }
            #expect(abs(pair.midY - host.view.bounds.midY) < 3, "Reader actions must be centered: \(pair)")
        }
        #expect(Set(controls.compactMap { $0.identifier?.rawValue }) == ["documentInformation", "revealDocumentInFinder"])
        for control in controls {
            #expect(control.image != nil, "The rail action must have a visible SF Symbol")
            let rect = control.convert(control.bounds, to: host.view)
            #expect(rect.minX >= 0 && rect.maxX <= 38, "Rail action is outside the shared column: \(rect)")
            #expect(rect.minY >= 0 && rect.maxY <= host.view.bounds.height, "Long navigation must keep both actions visible")
        }
    }

    @Test func finderActionRevealsTheCurrentPathAfterRename() async throws {
        _ = NSApplication.shared
        let domain = "local.luma.rail-finder.\(UUID())"
        let preferences = try #require(UserDefaults(suiteName: domain))
        defer { preferences.removePersistentDomain(forName: domain) }
        let workspace = chineseWorkspace(preferences: preferences)
        let tab = DocumentTab(url: URL(fileURLWithPath: "/tmp/original.md"))
        var revealed: URL?
        let host = NSHostingView(rootView: DocumentReaderRail(tab: tab, workspace: workspace,
            showingInformation: .constant(false), reveal: { revealed = $0 }) { Spacer(minLength: 0) }
            .frame(width: 38, height: 300))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 38, height: 300),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        defer { window.close() }
        let controls = try await waitForButtons(in: host)
        let finder = try #require(controls.first { $0.identifier?.rawValue == "revealDocumentInFinder" })
        let renamed = URL(fileURLWithPath: "/tmp/renamed.md")
        tab.relocate(to: renamed, readingSession: nil)
        finder.performClick(nil)
        #expect(revealed == renamed)
    }
}
