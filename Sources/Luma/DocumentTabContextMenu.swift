import SwiftUI
import AppKit

nonisolated enum TabCloseScope: CaseIterable, Hashable {
    case current, others, left, right, all

    var title: String {
        switch self {
        case .current: readerText("关闭标签页")
        case .others: readerText("关闭其他标签页")
        case .left: readerText("关闭左侧标签页")
        case .right: readerText("关闭右侧标签页")
        case .all: readerText("关闭所有标签页")
        }
    }
}

/// A native event region avoids SwiftUI context-menu handling inside NSToolbar.
struct DocumentTabContextMenu: NSViewRepresentable {
    let tab: DocumentTab
    let workspace: Workspace

    func makeNSView(context: Context) -> DocumentTabMenuRegion {
        let view = DocumentTabMenuRegion()
        updateNSView(view, context: context)
        return view
    }
    func updateNSView(_ view: DocumentTabMenuRegion, context: Context) {
        view.tab = tab
        view.workspace = workspace
        view.installMonitorIfNeeded()
    }
    static func dismantleNSView(_ view: DocumentTabMenuRegion, coordinator: ()) {
        view.removeMonitor()
        view.tab = nil
        view.workspace = nil
    }
}

final class DocumentTabMenuRegion: NSView {
    var tab: DocumentTab?
    var workspace: Workspace?
    var presentMenu: (NSMenu, NSEvent, NSView) -> Void = { NSMenu.popUpContextMenu($0, with: $1, for: $2) }
    private var monitor: Any?
    var isMonitoring: Bool { monitor != nil }

    // This background region must never intercept selection, close, or scrolling.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow !== window { removeMonitor() }
        super.viewWillMove(toWindow: newWindow)
    }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        installMonitorIfNeeded()
    }
    func installMonitorIfNeeded() {
        guard window != nil, monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.rightMouseDown, .leftMouseDown]) { [weak self] event in
            self?.handleContextMenuEvent(event) == true ? nil : event
        }
    }
    func removeMonitor() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }

    @discardableResult func handleContextMenuEvent(_ event: NSEvent) -> Bool {
        guard event.type == .rightMouseDown || (event.type == .leftMouseDown && event.modifierFlags.contains(.control)),
              let window, event.window === window, !isHiddenOrHasHiddenAncestor else { return false }
        let point = convert(event.locationInWindow, from: nil)
        guard bounds.contains(point), visibleRect.contains(point) else { return false }
        // SwiftUI can clip horizontally scrolling tabs without clipping each native
        // descendant's bounds. Also enforce the real toolbar scroll viewport.
        if let itemView = window.toolbar?.items.compactMap(\.view).first(where: { isDescendant(of: $0) }),
           let viewport = WorkspaceTabViewport.find(in: itemView),
           !viewport.bounds.contains(viewport.convert(event.locationInWindow, from: nil)) { return false }
        guard let menu = menu(for: event) else { return false }
        presentMenu(menu, event, self)
        return true
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        guard let tab, let workspace, workspace.tabs.contains(where: { $0 === tab }) else { return nil }
        let menu = NSMenu()
        menu.autoenablesItems = false
        for (index, scope) in TabCloseScope.allCases.enumerated() {
            let ids = workspace.tabIDs(toClose: scope, relativeTo: tab.id)
            let item = NSMenuItem(title: scope.title, action: #selector(performMenuAction(_:)), keyEquivalent: "")
            item.target = self
            item.tag = index
            item.representedObject = ids
            item.isEnabled = !ids.isEmpty && workspace.canCloseTabs
            menu.addItem(item)
        }
        menu.addItem(.separator())
        let reveal = NSMenuItem(title: readerText("在 Finder 中显示"), action: #selector(performMenuAction(_:)), keyEquivalent: "")
        reveal.target = self
        reveal.tag = -1
        menu.addItem(reveal)
        return menu
    }

    @objc private func performMenuAction(_ sender: NSMenuItem) {
        guard let tab, let workspace else { return }
        if sender.tag == -1 {
            NSWorkspace.shared.activateFileViewerSelecting([tab.url])
        } else if sender.isEnabled, let ids = sender.representedObject as? [URL] {
            Task { await workspace.closeTabs(ids) }
        }
    }
}
