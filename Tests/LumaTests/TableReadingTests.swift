import AppKit
import SwiftUI
import Testing
import ReaderCore
@testable import Luma

@MainActor @Suite(.serialized) struct TableReadingTests {
    @Test func filtersCombineAndKeepOriginalSourceLines() throws {
        let table = try CSVDocument("name,status,score\na,pending,10\nb,done,2\nc,pending,3\nd,,\ne,pending,20")
        let state = TableReadingState(); state.update(table)
        state.setFilter(.init(values: ["pending"]), column: 1)
        #expect(state.visibleRows == [1, 3, 5])
        state.setFilter(.init(query: "a"), column: 0)
        #expect(state.visibleRows == [1] && state.sourceLine(1) == 2)
        #expect(state.facets(column: 0).map(\.value) == ["a", "c", "e"])
        state.reset(); #expect(state.visibleRows == [1, 2, 3, 4, 5])
        state.setFilter(.init(values: [""]), column: 1)
        #expect(state.visibleRows == [4])
        state.setFilter(.init(values: []), column: 1)
        #expect(state.visibleRows.isEmpty)
        #expect(table.rows[1] == ["a", "pending", "10"])
    }
    @Test func numericSortRetainsPrecisionAndStableTies() throws {
        let state = TableReadingState()
        state.update(try CSVDocument("value\n9007199254740993\n9007199254740992\n2\n10\n2"))
        state.sort(column: 0, ascending: true)
        #expect(state.visibleRows == [3, 5, 4, 2, 1])
        state.sort(column: 0, ascending: false)
        #expect(state.visibleRows == [1, 2, 4, 3, 5])
        state.reset(); #expect(state.visibleRows == [1, 2, 3, 4, 5])
    }
    @Test func reloadRetainsValidConditionsAndDropsRemovedColumns() throws {
        let state = TableReadingState()
        state.update(try CSVDocument("a,b\n1,yes\n2,no"))
        state.setFilter(.init(values: ["yes"]), column: 1)
        state.sort(column: 1, ascending: true)
        state.update(try CSVDocument("a,b\n1,no\n2,yes"))
        #expect(state.visibleRows == [2])
        state.update(try CSVDocument("a\n1\n2"))
        #expect(state.filters.isEmpty && state.sortColumn == nil && state.visibleRows == [1, 2])
        state.update(try CSVDocument("")); #expect(state.visibleRows.isEmpty && state.columnCount == 0)
    }
    private func findTable(_ view: NSView) -> NSTableView? {
        if let table = view as? NSTableView { return table }
        return view.subviews.lazy.compactMap { findTable($0) }.first
    }
    private func waitForView(_ host: NSView, condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(3)
        while ContinuousClock.now < deadline {
            host.layoutSubtreeIfNeeded()
            if condition() { return }
            try await Task.sleep(for: .milliseconds(20))
        }
        try #require(condition(), "Native table did not update")
    }
    @Test func nativeTableUpdatesForSameCountSortAndFilterAndFitsWindow() async throws {
        _ = NSApplication.shared
        let state = TableReadingState()
        state.update(try CSVDocument("name,status\nz,pending\na,done\nb,pending"))
        let host = NSHostingView(rootView: TableReader(state: state))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 440), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = host
        defer { window.contentView = nil; window.close() }
        host.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(150))
        let table = try #require(findTable(host))
        #expect(table.numberOfRows == 3 && table.tableColumns.count == 3)
        state.sort(column: 0, ascending: true)
        try await waitForView(host) {
            guard let table = findTable(host), let cell = table.view(atColumn: 1, row: 0, makeIfNecessary: true) as? NSTextField else { return false }
            return cell.stringValue == "a"
        }
        let sortedTable = try #require(findTable(host))
        let label = try #require(sortedTable.view(atColumn: 1, row: 0, makeIfNecessary: true) as? NSTextField)
        #expect(label.stringValue == "a")
        state.setFilter(.init(values: ["pending"]), column: 1)
        try await waitForView(host) { findTable(host)?.numberOfRows == 2 }
        let filteredTable = try #require(findTable(host))
        #expect(filteredTable.numberOfRows == 2)
        state.widthMode = .fit
        try await Task.sleep(for: .milliseconds(150))
        let before = filteredTable.tableColumns[1].width
        window.setContentSize(NSSize(width: 420, height: 440)); host.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(150))
        #expect((findTable(host)?.tableColumns[1].width ?? before) < before)
        #expect(state.sourceLine(state.visibleRows[0]) == 4)
    }
    @Test func realSampleRemainsReadableInNarrowWindow() async throws {
        _ = NSApplication.shared
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(contentsOf: root.appendingPathComponent("Sources/Luma/Resources/Samples/阅读清单.csv"), encoding: .utf8)
        let state = TableReadingState(); state.update(try CSVDocument(source)); state.widthMode = .fit
        let host = NSHostingView(rootView: TableReader(state: state).foregroundStyle(LumaTheme.ink).background(LumaTheme.paper))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 420, height: 400), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.appearance = NSAppearance(named: .aqua); window.contentView = host
        defer { window.contentView = nil; window.close() }
        try await waitForView(host) { findTable(host)?.numberOfRows == 5 }
        #expect(host.frame.width <= 420)
        let table = try #require(findTable(host))
        #expect(table.tableColumns.reduce(0) { $0 + $1.width } <= (table.enclosingScrollView?.contentSize.width ?? 420) + 1)
        if let path = ProcessInfo.processInfo.environment["LUMA_CODE_PREVIEW_DIR"], let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) {
            host.cacheDisplay(in: host.bounds, to: bitmap)
            let directory = URL(fileURLWithPath: path)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let png = try #require(bitmap.representation(using: .png, properties: [:]))
            try png.write(to: directory.appendingPathComponent("table-narrow.png"))
        }
    }

    @Test(arguments: [false, true])
    func csvWindowKeepsChromeAndRailSeparateFromTableSelection(dark: Bool) async throws {
        _ = NSApplication.shared
        let domain = "local.luma.table-chrome.\(UUID())"
        let preferences = try #require(UserDefaults(suiteName: domain))
        defer { preferences.removePersistentDomain(forName: domain) }
        let workspace = Workspace(preferences: preferences)
        let samples = try #require(workspace.samplesURL)
        let names = ["欢迎.md", "源码编辑.md", "阅读清单.csv", "长文档导航.md", "正文搜索.md", "项目.json"]
        workspace.open(names.map { samples.appendingPathComponent($0) })
        for opened in workspace.tabs { await opened.loadTask?.value }
        let tab = try #require(workspace.tabs.first { $0.kind == .table })
        workspace.activeID = tab.id
        let host = NSHostingController(rootView: WorkspaceView(workspace: workspace).environment(\.colorScheme, dark ? .dark : .light))
        let window = NSWindow(contentViewController: host)
        window.isReleasedWhenClosed = false
        window.toolbarStyle = .unified
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        window.setContentSize(NSSize(width: 900, height: 600))
        defer { window.toolbar = nil; window.delegate = nil; window.close() }
        func railButtons(_ view: NSView) -> [DocumentRailNativeButton] {
            (view as? DocumentRailNativeButton).map { [$0] } ?? view.subviews.flatMap { railButtons($0) }
        }
        try await waitForView(host.view) { findTable(host.view) != nil && railButtons(host.view).count == 2 }
        let native = try #require(findTable(host.view))
        let delegate = ToolbarLayoutTests.ToolbarDelegate(workspace: workspace, tab: tab)
        if window.toolbar == nil {
            let toolbar = NSToolbar(identifier: "csv-chrome-\(UUID())")
            toolbar.delegate = delegate; window.toolbar = toolbar
        }
        if #available(macOS 26.0, *) {
            let toolbar = try #require(window.toolbar)
            let item = try #require(toolbar.items.first(where: { $0.view.map { WorkspaceTabViewport.find(in: $0) != nil } ?? false }))
            // Exercise AppKit's whole-item emphasis; it must not replace per-file selection.
            item.style = .prominent
            item.backgroundTintColor = LumaTheme.nativeAccent
            toolbar.selectedItemIdentifier = item.itemIdentifier
        }
        for width: CGFloat in [1641, 900, 690] {
            window.setContentSize(NSSize(width: width, height: 600))
            host.view.layoutSubtreeIfNeeded()
            native.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
            _ = window.makeFirstResponder(native)
            try await Task.sleep(for: .milliseconds(100))
            let controls = railButtons(host.view)
            let bounds = controls.map { $0.convert($0.bounds, to: host.view) }.reduce(NSRect.null) { $0.union($1) }
            #expect(abs(bounds.midY - host.view.bounds.midY) < 3, "File actions must stay vertically centered in CSV: \(bounds)")
            if #available(macOS 26.0, *), let toolbar = window.toolbar,
               let item = toolbar.items.first(where: { $0.view.map { WorkspaceTabViewport.find(in: $0) != nil } ?? false }) {
                #expect(item.style == .plain && item.backgroundTintColor == nil)
                #expect(toolbar.selectedItemIdentifier != item.itemIdentifier)
            }
            #expect(window.backgroundColor.usingColorSpace(.sRGB) == LumaTheme.nativePaper.usingColorSpace(.sRGB))
            let frame = try #require(window.contentView?.superview)
            frame.layoutSubtreeIfNeeded()
            let bitmap = try #require(frame.bitmapImageRepForCachingDisplay(in: frame.bounds))
            frame.cacheDisplay(in: frame.bounds, to: bitmap)
            func renderedColor(at point: NSPoint) throws -> NSColor {
                let x = Int(point.x / frame.bounds.width * CGFloat(bitmap.pixelsWide))
                let y = Int((frame.isFlipped ? point.y : frame.bounds.height - point.y) / frame.bounds.height * CGFloat(bitmap.pixelsHigh))
                return try #require(bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB))
            }
            let scroll = try #require(findTable(host.view)?.enclosingScrollView)
            let scrollFrame = scroll.convert(scroll.bounds, to: frame)
            // Compare surfaces from the same render, including the same display color profile.
            let paper = try renderedColor(at: NSPoint(x: scrollFrame.minX - 19, y: scrollFrame.maxY - 40))
            func expectPaper(at point: NSPoint) throws {
                let color = try renderedColor(at: point)
                let difference = max(abs(color.redComponent - paper.redComponent),
                                     abs(color.greenComponent - paper.greenComponent),
                                     abs(color.blueComponent - paper.blueComponent))
                #expect(difference < 0.015, "The whole operation surface must match the reader paper at \(point); got \(color)")
            }
            // Sample blank portions across the whole window bar, not just the file-list host.
            for fraction: CGFloat in [0.35, 0.6, 0.85] {
                try expectPaper(at: NSPoint(x: frame.bounds.width * fraction, y: frame.bounds.maxY - 8))
            }
            if let scroll = findTable(host.view)?.enclosingScrollView {
                let rect = scroll.convert(scroll.bounds, to: frame)
                try expectPaper(at: NSPoint(x: rect.minX + 4, y: rect.maxY + 3))
            }
            if let path = ProcessInfo.processInfo.environment["LUMA_CSV_CHROME_DIR"] {
                let folder = URL(fileURLWithPath: path)
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                try #require(bitmap.representation(using: .png, properties: [:])).write(to: folder.appendingPathComponent("csv-window-\(dark ? "dark" : "light")-\(Int(width)).png"))
            }
        }
    }

}
