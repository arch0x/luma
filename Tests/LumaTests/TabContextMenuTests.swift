import AppKit
import SwiftUI
import Testing
@testable import Luma

@MainActor @Suite(.serialized) struct TabContextMenuTests {
    private func regions(in view: NSView) -> [DocumentTabMenuRegion] {
        (view as? DocumentTabMenuRegion).map { [$0] } ?? view.subviews.flatMap { regions(in: $0) }
    }

    private func toolbarRegions(_ window: NSWindow) -> [DocumentTabMenuRegion] {
        window.toolbar?.items.compactMap(\.view).flatMap { regions(in: $0) } ?? []
    }

    private func visibleBounds(of region: DocumentTabMenuRegion) -> NSRect {
        var visible = region.bounds.intersection(region.visibleRect)
        if let item = region.window?.toolbar?.items.compactMap(\.view).first(where: { region.isDescendant(of: $0) }),
           let viewport = WorkspaceTabViewport.find(in: item) {
            visible = visible.intersection(region.convert(viewport.bounds, from: viewport))
        }
        return visible
    }

    private func visibleRegion(for tab: DocumentTab, in window: NSWindow, count: Int) async throws -> DocumentTabMenuRegion {
        let deadline = ContinuousClock.now + .seconds(8)
        while ContinuousClock.now < deadline {
            window.displayIfNeeded()
            window.contentView?.superview?.layoutSubtreeIfNeeded()
            let views = toolbarRegions(window)
            if views.count == count, let region = views.first(where: { $0.tab === tab && $0.window === window && $0.isMonitoring }),
               !region.isHiddenOrHasHiddenAncestor {
                if visibleBounds(of: region).width >= 30 { return region }
                region.scrollToVisible(region.bounds)
            }
            // Layout may replace the representable: reacquire it rather than retaining
            // a detached native view across a SwiftUI toolbar update.
            try await Task.sleep(for: .milliseconds(20))
        }
        let geometry = window.toolbar?.items.map { item in
            "\(item.itemIdentifier.rawValue): frame=\(String(describing: item.view?.frame)), windowFrame=\(String(describing: item.view.map { $0.convert($0.bounds, to: nil) })), attached=\(item.view?.window === window)"
        }.joined(separator: "; ") ?? "No toolbar"
        Issue.record("Target tab did not become visible: window=\(window.frame), mode=\(String(describing: window.toolbar?.displayMode)), toolbar=\(geometry)")
        throw URLError(.timedOut)
    }

    private func event(_ type: NSEvent.EventType, in region: DocumentTabMenuRegion,
                       flags: NSEvent.ModifierFlags = []) throws -> NSEvent {
        let window = try #require(region.window)
        let visible = visibleBounds(of: region)
        try #require(!visible.isEmpty, "A real click must fall inside the clipped tab viewport")
        let point = region.convert(NSPoint(x: visible.midX, y: visible.midY), to: nil)
        return try #require(NSEvent.mouseEvent(with: type, location: point, modifierFlags: flags,
            timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
            context: nil, eventNumber: 1, clickCount: 1, pressure: 1))
    }

    @Test func realToolbarRightClickAndControlClickPresentTheClickedFilesMenu() async throws {
        _ = NSApplication.shared
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let domain = "local.luma.native-tab-menu.\(UUID())"
        let preferences = try #require(UserDefaults(suiteName: domain))
        defer { try? FileManager.default.removeItem(at: directory); preferences.removePersistentDomain(forName: domain) }
        let workspace = chineseWorkspace(preferences: preferences)
        let files = try (0..<3).map { index in
            let file = directory.appendingPathComponent("note-\(index).txt")
            try Data("original \(index)".utf8).write(to: file)
            return file
        }
        workspace.open(files)
        let tabs = workspace.tabs
        for tab in tabs { await tab.loadTask?.value }
        workspace.activeID = tabs[0].id
        let host = NSHostingView(rootView: WorkspaceView(workspace: workspace))
        let window = ReaderTestWindow(contentRect: NSRect(x: 0, y: 0, width: 1320, height: 600),
                              styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        // Match the app Scene rather than AppKit's platform-dependent automatic style.
        window.toolbarStyle = .unified
        window.contentView = host
        window.makeKeyAndOrderFront(nil)
        defer { window.delegate = nil; window.close() }
        let middle = try await visibleRegion(for: tabs[1], in: window, count: 3)
        let views = toolbarRegions(window)
        #expect(views.count == 3)
        #expect(middle.isMonitoring && middle.window === window)
        #expect(middle.hitTest(.zero) == nil, "The native menu bridge must not block normal tab buttons")
        var captured: NSMenu?
        var presentations = 0
        for region in views {
            region.presentMenu = { menu, _, _ in captured = menu; presentations += 1 }
        }
        // Exercise the exact event handler installed by the native monitor, against
        // real toolbar geometry rather than only testing the close-target helpers.
        let secondaryClick = try event(.rightMouseDown, in: middle)
        #expect(middle.handleContextMenuEvent(secondaryClick))
        let menu = try #require(captured, "Right-click in the real toolbar must present a menu")
        #expect(presentations == 1 && workspace.activeID == tabs[0].id)
        for sibling in views where sibling !== middle {
            #expect(!sibling.handleContextMenuEvent(secondaryClick), "A neighboring tab must not consume this click")
        }
        #expect(presentations == 1)
        #expect(menu.items.filter { !$0.isSeparatorItem }.map(\.title) == TabCloseScope.allCases.map(\.title) + ["在 Finder 中显示"])
        let right = try #require(menu.items.first { $0.title == TabCloseScope.right.title })
        #expect(right.representedObject as? [URL] == [tabs[2].id])
        captured = nil
        #expect(middle.handleContextMenuEvent(try event(.leftMouseDown, in: middle, flags: .control)))
        #expect(captured != nil && presentations == 2 && workspace.activeID == tabs[0].id)
        #expect(!middle.handleContextMenuEvent(try event(.leftMouseDown, in: middle)))
        let removed = try #require(views.first { $0.tab === tabs[2] })
        #expect(NSApp.sendAction(try #require(right.action), to: right.target, from: right))
        let closingDeadline = ContinuousClock.now + .seconds(3)
        while workspace.tabs.count != 2 && ContinuousClock.now < closingDeadline { try await Task.sleep(for: .milliseconds(20)) }
        #expect(workspace.tabs.map(\.id) == [tabs[0].id, tabs[1].id])
        #expect(workspace.activeID == tabs[0].id)
        let currentMiddle = try await visibleRegion(for: tabs[1], in: window, count: 2)
        let lastMenu = try #require(currentMiddle.menu(for: try event(.rightMouseDown, in: currentMiddle)))
        #expect(lastMenu.items.first { $0.title == TabCloseScope.right.title }?.isEnabled == false)
        let removalDeadline = ContinuousClock.now + .seconds(3)
        while removed.isMonitoring && ContinuousClock.now < removalDeadline {
            host.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(!removed.isMonitoring, "Closing a tab must remove its native event monitor")
    }
}
