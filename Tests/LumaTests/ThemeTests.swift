import AppKit
import SwiftUI
import Testing
@testable import Luma

@MainActor @Suite(.serialized) struct ThemeTests {
    @Test(arguments: [false, true])
    func navigationStaysGreenWithBlueAncestorAccent(dark: Bool) async throws {
        _ = NSApplication.shared
        let domain = "local.luma.theme-tests.\(UUID().uuidString)"
        let preferences = try #require(UserDefaults(suiteName: domain))
        defer { preferences.removePersistentDomain(forName: domain) }
        let workspace = Workspace(preferences: preferences)
        workspace.roots = [URL(fileURLWithPath: "/tmp/工作文档")]
        let tab = DocumentTab(url: URL(fileURLWithPath: "/tmp/阅读.md"))
        let state = MarkdownRenderState()
        state.loading = false
        state.headings = [MarkdownHeading(id: "current", title: "当前阅读章节", level: 1),
                          MarkdownHeading(id: "next", title: "下一章节", level: 1)]
        state.activeHeadingID = "current"
        let content = HStack(spacing: 0) {
            WorkspaceView(workspace: workspace).frame(width: 960)
            MarkdownOutlineView(state: state, tab: tab).frame(width: 240)
        }
        // Reproduce the system-blue ancestor that used to leak into custom shapes and labels.
        .accentColor(.blue).tint(.blue)
        .environment(\.colorScheme, dark ? .dark : .light)
        .frame(width: 1200, height: 800)
        .background(Color(nsColor: .windowBackgroundColor))
        let hosting = NSHostingView(rootView: content)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1200, height: 800),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        window.contentView = hosting
        defer { window.delegate = nil; window.close() }
        hosting.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(150))
        hosting.layoutSubtreeIfNeeded()
        let bitmap = try #require(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
        hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
        if let path = ProcessInfo.processInfo.environment["LUMA_THEME_PREVIEW_DIR"] {
            let directory = URL(fileURLWithPath: path)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let png = try #require(bitmap.representation(using: .png, properties: [:]))
            try png.write(to: directory.appendingPathComponent("theme-\(dark ? "dark" : "light").png"))
        }
        func sidebarRow(in view: NSView) -> SidebarRowView? {
            if let row = view as? SidebarRowView { return row }
            return view.subviews.lazy.compactMap { sidebarRow(in: $0) }.first
        }
        let row = try #require(sidebarRow(in: hosting))
        #expect(row.label.rootView.colorScheme == (dark ? .dark : .light))
        #expect(row.label.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == (dark ? .darkAqua : .aqua))
        let rowBitmap = try #require(row.bitmapImageRepForCachingDisplay(in: row.bounds))
        row.cacheDisplay(in: row.bounds, to: rowBitmap)
        var readableGlyphPixels = 0
        for x in Int(50 * CGFloat(rowBitmap.pixelsWide) / row.bounds.width)..<Int(min(CGFloat(rowBitmap.pixelsWide), 120 * CGFloat(rowBitmap.pixelsWide) / row.bounds.width)) {
            for y in 0..<rowBitmap.pixelsHigh {
                guard let rgb = rowBitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { continue }
                let neutral = abs(rgb.redComponent - rgb.greenComponent) < 0.08 && abs(rgb.greenComponent - rgb.blueComponent) < 0.08
                if neutral && (dark ? rgb.redComponent > 0.6 : rgb.redComponent < 0.3) { readableGlyphPixels += 1 }
            }
        }
        #expect(readableGlyphPixels > 15, "Native directory names must stay readable in either appearance")
        func counts(from start: Double, to end: Double) -> (green: Int, blue: Int) {
            var green = 0, blue = 0
            for x in stride(from: Int(start * Double(bitmap.pixelsWide)), to: Int(end * Double(bitmap.pixelsWide)), by: 2) {
                for y in stride(from: 0, to: bitmap.pixelsHigh, by: 2) {
                    guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { continue }
                    if color.greenComponent > color.redComponent * 1.2 && color.greenComponent > color.blueComponent * 1.08 { green += 1 }
                    if color.blueComponent > color.greenComponent * 1.15 && color.blueComponent > color.redComponent * 1.25 { blue += 1 }
                }
            }
            return (green, blue)
        }
        let sidebar = counts(from: 0, to: 0.20)
        let outline = counts(from: 0.80, to: 1)
        #expect(sidebar.green > 30, "Brand and folder should render green")
        #expect(sidebar.blue == 0, "System blue must not leak into the sidebar")
        #expect(outline.green > 10, "Current heading should render green")
        #expect(outline.blue == 0, "System blue must not leak into the outline")
    }

    @Test(arguments: [false, true])
    func nativeEditorSelectionUsesGreenInBothAppearances(dark: Bool) throws {
        _ = NSApplication.shared
        let tab = DocumentTab(url: URL(fileURLWithPath: "/tmp/theme.txt"))
        let editor = tab.sourceEditor()
        let appearance = try #require(NSAppearance(named: dark ? .darkAqua : .aqua))
        editor.textView.appearance = appearance
        editor.replaceFromDisk("阅读 Luma")
        editor.textView.setSelectedRange(NSRange(location: 0, length: 2))
        let selection = try #require(editor.textView.selectedTextAttributes[.backgroundColor] as? NSColor)
        let colors: [NSColor] = [selection, editor.textView.insertionPointColor]
        var resolved: [NSColor?] = []
        appearance.performAsCurrentDrawingAppearance {
            resolved = colors.map { $0.usingColorSpace(.sRGB) }
        }
        for color in resolved {
            let rgb = try #require(color)
            #expect(rgb.greenComponent > rgb.redComponent)
            #expect(rgb.greenComponent > rgb.blueComponent)
        }
        #expect(editor.textView.string == "阅读 Luma")
        #expect(editor.textView.selectedRange() == NSRange(location: 0, length: 2))
    }
}
