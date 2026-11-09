import AppKit
import SwiftUI
import Testing
import WebKit
@testable import Luma

@MainActor @Suite(.serialized) struct ThemeTests {
    @Test func bundledLongDocumentAdaptsInTheWorkspaceWindow() async throws {
        _ = NSApplication.shared
        let domain = "local.luma.reader-layout.\(UUID().uuidString)"
        let preferences = try #require(UserDefaults(suiteName: domain))
        defer { preferences.removePersistentDomain(forName: domain) }
        let workspace = Workspace(preferences: preferences)
        let samples = try #require(workspace.samplesURL)
        workspace.addFolder(samples)
        workspace.open([samples.appendingPathComponent("欢迎.md"), samples.appendingPathComponent("长文档导航.md")])
        let tab = try #require(workspace.activeTab)
        try #require(tab.title == "长文档导航.md")
        let host = NSHostingView(rootView: WorkspaceView(workspace: workspace))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1_240, height: 740),
                              styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .aqua)
        window.contentView = host
        defer { window.delegate = nil; window.close() }

        func webView(in view: NSView) -> WKWebView? {
            if let web = view as? WKWebView { return web }
            return view.subviews.lazy.compactMap { webView(in: $0) }.first
        }

        func waitForWeb(where condition: (WKWebView) async -> Bool) async throws -> WKWebView {
            let deadline = ContinuousClock.now + .seconds(10)
            while ContinuousClock.now < deadline {
                host.layoutSubtreeIfNeeded()
                if let web = webView(in: host), await condition(web) { return web }
                try await Task.sleep(for: .milliseconds(25))
            }
            let web = webView(in: host)
            Issue.record("The real workspace window did not reach the requested reading layout: window=\(String(describing: window.contentView?.bounds)), web=\(String(describing: web?.bounds)), metrics=\(tab.markdownRenderState.metrics), error=\(tab.markdownRenderState.error ?? "none")")
            throw URLError(.timedOut)
        }

        let wide = try await waitForWeb { web in
            (try? await web.evaluateJavaScript("window.luma?.lastResult?.diagrams === 1")) as? Bool == true
                && web.bounds.width > 940 && web.bounds.width < 995
        }
        #expect(window.titlebarAppearsTransparent)
        #expect(window.titlebarSeparatorStyle == .none)
        window.effectiveAppearance.performAsCurrentDrawingAppearance {
            #expect(window.backgroundColor.usingColorSpace(.sRGB) == LumaTheme.nativePaper.usingColorSpace(.sRGB))
        }
        #expect(wide.bounds.height >= 725, "Document actions belong in the window toolbar, leaving no second header")
        try await captureWorkspace(host, web: wide, named: "workspace-light-wide")
        let readerLeft = wide.convert(wide.bounds, to: host).minX
        #expect((260...290).contains(readerLeft), "The preview begins after the library and the permanent rail")
        _ = try await wide.evaluateJavaScript("window.luma.navigateToHeading('公式与图表之间')")

        window.setContentSize(NSSize(width: 690, height: 510))
        let narrow = try await waitForWeb { web in
            guard (390...510).contains(web.bounds.width) else { return false }
            let stable = try? await web.evaluateJavaScript("""
            document.documentElement.scrollWidth === window.innerWidth &&
            window.luma.getReadingPosition().headingID === '公式与图表之间'
            """)
            return stable as? Bool == true
        }
        #expect(narrow === wide, "Resizing must retain the running preview")
        #expect(narrow.bounds.height >= 495, "A narrow window must not stack extra toolbars")
        #expect(abs(narrow.convert(narrow.bounds, to: host).minX - readerLeft) < 2)
        window.appearance = NSAppearance(named: .darkAqua)
        let dark = try await waitForWeb { web in
            (try? await web.evaluateJavaScript("""
            getComputedStyle(document.documentElement).backgroundColor === 'rgb(26, 32, 43)' &&
            window.luma.getReadingPosition().headingID === '公式与图表之间'
            """)) as? Bool == true
        }
        #expect(dark === narrow)
        window.effectiveAppearance.performAsCurrentDrawingAppearance {
            #expect(window.backgroundColor.usingColorSpace(.sRGB) == LumaTheme.nativePaper.usingColorSpace(.sRGB))
        }
        try await captureWorkspace(host, web: dark, named: "workspace-dark-narrow")

        let library = try #require(workspace.libraryRegion)
        let libraryPoint = library.convert(NSPoint(x: 20, y: 90), to: nil)
        let documentPoint = dark.convert(NSPoint(x: 70, y: 90), to: nil)
        for point in [libraryPoint, documentPoint] {
            let event = try #require(NSEvent.mouseEvent(with: .leftMouseDown, location: point, modifierFlags: [],
                                                       timestamp: 0, windowNumber: window.windowNumber,
                                                       context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
            workspace.recordFindFocus(from: event, in: window)
            workspace.openFocusedFind(in: window)
            if point == libraryPoint {
                #expect(workspace.libraryFindFocusRequest == 1)
                #expect(!workspace.showFind)
            } else {
                #expect(workspace.libraryFindFocusRequest == 1)
                #expect(workspace.showFind && workspace.findFocusRequest == 1)
            }
        }
    }

    private func captureWorkspace(_ host: NSView, web: WKWebView, named name: String) async throws {
        guard let path = ProcessInfo.processInfo.environment["LUMA_THEME_PREVIEW_DIR"] else { return }
        let page = try await web.takeSnapshot(configuration: nil)
        let chrome = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: chrome)
        let size = host.bounds.size
        var pageFrame = web.convert(web.bounds, to: host)
        if host.isFlipped { pageFrame.origin.y = size.height - pageFrame.maxY }
        let image = NSImage(size: size, flipped: false) { rect in
            chrome.draw(in: rect)
            page.draw(in: pageFrame)
            return true
        }
        let tiff = try #require(image.tiffRepresentation)
        let bitmap = try #require(NSBitmapImageRep(data: tiff))
        let png = try #require(bitmap.representation(using: .png, properties: [:]))
        let directory = URL(fileURLWithPath: path, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try png.write(to: directory.appendingPathComponent("\(name).png"))
    }

    @Test(arguments: [false, true])
    func navigationKeepsThemeColorsWithPurpleAncestorAccent(dark: Bool) async throws {
        _ = NSApplication.shared
        let domain = "local.luma.theme-tests.\(UUID().uuidString)"
        let preferences = try #require(UserDefaults(suiteName: domain))
        defer { preferences.removePersistentDomain(forName: domain) }
        let workspace = Workspace(preferences: preferences)
        workspace.roots = [URL(fileURLWithPath: "/tmp/工作文档")]
        let state = MarkdownRenderState()
        state.loading = false
        state.headings = [MarkdownHeading(id: "current", title: "当前阅读章节", level: 1),
                          MarkdownHeading(id: "next", title: "下一章节", level: 1)]
        state.activeHeadingID = "current"
        let content = HStack(spacing: 0) {
            WorkspaceView(workspace: workspace).frame(width: 960)
            MarkdownSectionRail(state: state, peek: MarkdownSectionPeek()).frame(width: 240, alignment: .trailing)
        }
        .accentColor(.purple).tint(.purple)
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
                if dark ? rgb.redComponent > 0.65 : rgb.redComponent < 0.3 { readableGlyphPixels += 1 }
            }
        }
        #expect(readableGlyphPixels > 15, "Native directory names must stay readable in either appearance")
        func counts(from start: Double, to end: Double) -> (purple: Int, blue: Int, current: Int) {
            var purple = 0, blue = 0, current = 0
            for x in stride(from: Int(start * Double(bitmap.pixelsWide)), to: Int(end * Double(bitmap.pixelsWide)), by: 2) {
                for y in stride(from: 0, to: bitmap.pixelsHigh, by: 2) {
                    guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { continue }
                    if color.redComponent > color.greenComponent * 1.2 && color.blueComponent > color.greenComponent * 1.2 { purple += 1 }
                    if color.blueComponent > color.greenComponent * 1.12 && color.greenComponent > color.redComponent * 1.12 { blue += 1 }
                    let brightest = max(color.redComponent, color.greenComponent, color.blueComponent)
                    let darkest = min(color.redComponent, color.greenComponent, color.blueComponent)
                    if dark ? darkest > 0.90 : brightest < 0.50 { current += 1 }
                }
            }
            return (purple, blue, current)
        }
        let sidebar = counts(from: 0, to: 0.20)
        let outline = counts(from: 0.80, to: 1)
        #expect(sidebar.blue > 7, "The folder should render blue")
        #expect(sidebar.purple == 0, "Ancestor tint must not leak into the sidebar")
        #expect(outline.current > 5, "The current mark should render white in dark mode and dark ink in light mode")
        #expect(outline.purple == 0, "Ancestor tint must not leak into the outline")
    }

    @Test(arguments: [false, true])
    func nativeEditorSelectionUsesBlueInBothAppearances(dark: Bool) throws {
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
            #expect(rgb.blueComponent > rgb.greenComponent)
            #expect(rgb.greenComponent > rgb.redComponent)
        }
        #expect(editor.textView.string == "阅读 Luma")
        #expect(editor.textView.selectedRange() == NSRange(location: 0, length: 2))
    }
}
