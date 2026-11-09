import AppKit
import SwiftUI
import Testing
@testable import Luma

@MainActor @Suite(.serialized) struct ToolbarLayoutTests {
    @MainActor final class Viewport { var width: CGFloat = 120 }

    @MainActor struct AdaptiveFiles: View {
        let width: CGFloat
        var body: some View {
            ScrollView(.horizontal) {
                HStack(spacing: 4) {
                    ForEach(0..<16) { index in
                        Text("document-\(index).md").font(.system(size: 12))
                            .padding(.horizontal, 8).frame(width: 140, height: 31)
                    }
                }
            }
            .scrollIndicators(.hidden)
            .frame(minWidth: 0, idealWidth: width, maxWidth: width)
            .frame(height: 31)
            .background(WorkspaceTabViewport())
        }
    }

    @MainActor final class ToolbarDelegate: NSObject, NSToolbarDelegate {
        let files = NSToolbarItem(itemIdentifier: .init("files"))
        let actions = NSToolbarItem(itemIdentifier: .init("actions"))
        let leading = NSToolbarItem(itemIdentifier: .init("leading"))
        var leadingWidth: NSLayoutConstraint?

        init(workspace: Workspace, tab: DocumentTab, viewport: Viewport? = nil) {
            super.init()
            let filesView: NSView
            if let viewport {
                filesView = NSHostingView(rootView: AdaptiveFiles(width: viewport.width))
                let leadingView = NSHostingView(rootView: Text("＋").frame(height: 31))
                leadingView.translatesAutoresizingMaskIntoConstraints = false
                leadingWidth = leadingView.widthAnchor.constraint(equalToConstant: 36)
                leadingWidth?.isActive = true
                leadingView.heightAnchor.constraint(equalToConstant: 38).isActive = true
                leading.view = leadingView
            } else {
                filesView = NSHostingView(rootView: Text("first.md   second.md").frame(width: 140, height: 31))
                filesView.widthAnchor.constraint(equalToConstant: 140).isActive = true
            }
            let actionsView = NSHostingView(rootView: DocumentToolbar(tab: tab, workspace: workspace)
                .background(WorkspaceToolbarAlignment(onTabViewportWidth: viewport.map { model in
                    { width in
                        model.width = width
                        // Mirror WorkspaceView's state-driven toolbar content update,
                        // including when AppKit has moved this host into overflow.
                        if let host = filesView as? NSHostingView<AdaptiveFiles> {
                            host.rootView = AdaptiveFiles(width: width)
                            host.layoutSubtreeIfNeeded()
                        }
                    }
                }).frame(width: 0, height: 0)))
            actionsView.widthAnchor.constraint(equalToConstant: DocumentToolbar.width).isActive = true
            files.view = filesView
            actions.view = actionsView
            for view in [filesView, actionsView] {
                view.translatesAutoresizingMaskIntoConstraints = false
                view.heightAnchor.constraint(equalToConstant: 38).isActive = true
            }
        }

        func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
            (leading.view == nil ? [] : [leading.itemIdentifier]) +
                [files.itemIdentifier, .flexibleSpace, actions.itemIdentifier, .flexibleSpace]
        }
        func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
            toolbarDefaultItemIdentifiers(toolbar)
        }
        func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier identifier: NSToolbarItem.Identifier,
                     willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
            if identifier == leading.itemIdentifier { return leading }
            if identifier == files.itemIdentifier { return files }
            if identifier == actions.itemIdentifier { return actions }
            return nil
        }
    }

    @Test(arguments: [690.0, 1180.0, 1600.0])
    func nativeToolbarPinsActionsToWindowEdge(width: Double) async throws {
        _ = NSApplication.shared
        let domain = "local.luma.toolbar-layout.\(UUID().uuidString)"
        let preferences = try #require(UserDefaults(suiteName: domain))
        defer { preferences.removePersistentDomain(forName: domain) }
        let workspace = Workspace(preferences: preferences)
        let samples = try #require(workspace.samplesURL)
        workspace.open([samples.appendingPathComponent("长文档导航.md")])
        let tab = try #require(workspace.activeTab)
        await tab.loadTask?.value
        let delegate = ToolbarDelegate(workspace: workspace, tab: tab)
        let toolbar = NSToolbar(identifier: "layout-\(UUID().uuidString)")
        toolbar.delegate = delegate
        toolbar.displayMode = .iconOnly
        toolbar.centeredItemIdentifiers = [delegate.actions.itemIdentifier]
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: 160),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.toolbarStyle = .unified
        window.titleVisibility = .hidden
        window.toolbar = toolbar
        defer { window.toolbar = nil; window.close() }

        for source in [false, true] {
            tab.showSource = source
            if source { tab.edit((tab.draft ?? "") + "\nmodified") }
            window.displayIfNeeded()
            let deadline = ContinuousClock.now + .seconds(2)
            while !toolbar.centeredItemIdentifiers.isEmpty && ContinuousClock.now < deadline {
                try await Task.sleep(for: .milliseconds(10))
            }
            try #require(toolbar.centeredItemIdentifiers.isEmpty, "The installed anchor must align the actual native toolbar automatically")
            // Repeated updates must not accumulate flexible space or shift the edge.
            WorkspaceToolbarAlignment.pin(delegate.actions, in: toolbar)
            window.displayIfNeeded()
            window.contentView?.superview?.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(50))
            let view = try #require(delegate.actions.view)
            let frameView = try #require(window.contentView?.superview)
            frameView.layoutSubtreeIfNeeded()
            let frame = view.convert(view.bounds, to: frameView)
            let gap = frameView.bounds.maxX - frame.maxX
            let filesView = try #require(delegate.files.view)
            let filesFrame = filesView.convert(filesView.bounds, to: frameView)
            #expect(filesFrame.minX < 160, "Files must start at the leading side of the native toolbar")
            #expect(filesFrame.maxX < frame.minX)
            #expect(toolbar.centeredItemIdentifiers.isEmpty)
            #expect(toolbar.items.last === delegate.actions)
            #expect(toolbar.items.filter { $0.itemIdentifier == .flexibleSpace }.count == 1)
            #expect(frame.width >= DocumentToolbar.width)
            #expect((0...28).contains(gap), "Actions must end at the window's right margin, not the middle: \(frame), gap \(gap), window \(frameView.bounds)")
            if let directory = ProcessInfo.processInfo.environment["LUMA_TOOLBAR_PREVIEW_DIR"] {
                let bitmap = try #require(frameView.bitmapImageRepForCachingDisplay(in: frameView.bounds))
                frameView.cacheDisplay(in: frameView.bounds, to: bitmap)
                let data = try #require(bitmap.representation(using: .png, properties: [:]))
                let folder = URL(fileURLWithPath: directory)
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                try data.write(to: folder.appendingPathComponent("toolbar-\(Int(width))-\(source ? "source" : "preview").png"))
            }
        }
    }

    @Test func fileViewportFillsSpaceAndResizesWithoutMovingActions() async throws {
        _ = NSApplication.shared
        let domain = "local.luma.adaptive-toolbar.\(UUID().uuidString)"
        let preferences = try #require(UserDefaults(suiteName: domain))
        defer { preferences.removePersistentDomain(forName: domain) }
        let workspace = Workspace(preferences: preferences)
        let tab = DocumentTab(url: URL(fileURLWithPath: "/tmp/adaptive.md"))
        tab.draft = "# Document"; tab.savedText = tab.draft
        tab.state = .ready(.markdown(tab.draft ?? ""))
        workspace.tabs = [tab]; workspace.activeID = tab.id
        let viewport = Viewport()
        let delegate = ToolbarDelegate(workspace: workspace, tab: tab, viewport: viewport)
        let toolbar = NSToolbar(identifier: "adaptive-\(UUID().uuidString)")
        toolbar.delegate = delegate
        toolbar.displayMode = .iconOnly
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 690, height: 160),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.toolbarStyle = .unified; window.titleVisibility = .hidden; window.toolbar = toolbar
        defer { window.toolbar = nil; window.close() }
        let filesView = try #require(delegate.files.view)
        let actionsView = try #require(delegate.actions.view)
        let frameView = try #require(window.contentView?.superview)
        for width: CGFloat in [690, 1180, 1600, 760] {
            if width == 760 { delegate.leadingWidth?.constant = 80 }
            tab.showSource = width == 1180
            if width == 1180 { tab.edit("modified") }
            window.setContentSize(NSSize(width: width, height: 160))
            let deadline = ContinuousClock.now + .seconds(3)
            var gap: CGFloat = .infinity
            while ContinuousClock.now < deadline {
                window.displayIfNeeded(); frameView.layoutSubtreeIfNeeded()
                let files = filesView.convert(filesView.bounds, to: frameView)
                let actions = actionsView.convert(actionsView.bounds, to: frameView)
                gap = actions.minX - files.maxX
                if files.width > 80 && (0...36).contains(gap) { break }
                try await Task.sleep(for: .milliseconds(10))
            }
            let files = filesView.convert(filesView.bounds, to: frameView)
            let actions = actionsView.convert(actionsView.bounds, to: frameView)
            #expect((0...36).contains(gap), "Tabs must extend to the actions: files \(files), actions \(actions), preferred \(viewport.width)")
            #expect((0...28).contains(frameView.bounds.maxX - actions.maxX))
            #expect(actions.width >= DocumentToolbar.width)
            if width == 1600 { #expect(files.width > 900, "A wide window must not cap tabs at 620") }
            if let directory = ProcessInfo.processInfo.environment["LUMA_TOOLBAR_PREVIEW_DIR"] {
                let bitmap = try #require(frameView.bitmapImageRepForCachingDisplay(in: frameView.bounds))
                frameView.cacheDisplay(in: frameView.bounds, to: bitmap)
                let data = try #require(bitmap.representation(using: .png, properties: [:]))
                let folder = URL(fileURLWithPath: directory)
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                try data.write(to: folder.appendingPathComponent("adaptive-\(Int(width)).png"))
            }
        }
    }

}
