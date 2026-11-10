import AppKit
import SwiftUI

/// Pins the actions against the actual window edge, independently of SwiftUI toolbar grouping.
struct WorkspaceToolbarAlignment: NSViewRepresentable {
    var onTabViewportWidth: ((CGFloat) -> Void)?

    func makeNSView(context: Context) -> Anchor {
        let view = Anchor()
        view.onTabViewportWidth = onTabViewportWidth
        return view
    }
    func updateNSView(_ view: Anchor, context: Context) {
        view.onTabViewportWidth = onTabViewportWidth
        view.scheduleAlignment()
    }
    static func dismantleNSView(_ view: Anchor, coordinator: ()) {
        view.stopObserving()
        view.onTabViewportWidth = nil
    }

    static func pin(_ actions: NSToolbarItem, in toolbar: NSToolbar) {
        guard let index = toolbar.items.firstIndex(where: { $0 === actions }) else { return }
        if !toolbar.centeredItemIdentifiers.isEmpty { toolbar.centeredItemIdentifiers = [] }
        if actions.visibilityPriority != .high { actions.visibilityPriority = .high }
        // Flexible space after the actions would share the spare width and center the group.
        for position in toolbar.items.indices.reversed() where position > index {
            if toolbar.items[position].itemIdentifier == .flexibleSpace { toolbar.removeItem(at: position) }
        }
        if index == 0 || toolbar.items[index - 1].itemIdentifier != .flexibleSpace {
            toolbar.insertItem(withItemIdentifier: .flexibleSpace, at: index)
        }
    }

    /// The item hosts many file tabs; only those tabs own a selected appearance.
    static func keepFileTabsNeutral(_ item: NSToolbarItem, in toolbar: NSToolbar) {
        if toolbar.selectedItemIdentifier == item.itemIdentifier { toolbar.selectedItemIdentifier = nil }
        if #available(macOS 26.0, *) {
            if item.style != .plain { item.style = .plain }
            if item.backgroundTintColor != nil { item.backgroundTintColor = nil }
        }
    }

    final class Anchor: NSView {
        var onTabViewportWidth: ((CGFloat) -> Void)?
        private var lastReportedWidth: CGFloat?
        private var lastLeadingInset: CGFloat?
        private var leadingItemGap: CGFloat = 12
        private var trailingInset: CGFloat = 8
        private weak var toolbarWindow: NSWindow?
        private var observers: [NSObjectProtocol] = []
        private var scheduled = false

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window else { return }
            // AppKit detaches item views while moving them into overflow. Keep tracking
            // the original window so a subsequent resize can bring the tabs back.
            if let toolbarWindow, toolbarWindow !== window, window.toolbar == nil { return }
            stopObserving()
            toolbarWindow = window
            for name in [NSWindow.didUpdateNotification, NSWindow.didResizeNotification] {
                observers.append(NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                    Task { @MainActor [weak self] in self?.scheduleAlignment() }
                })
            }
            scheduleAlignment()
        }

        func stopObserving() {
            for observer in observers { NotificationCenter.default.removeObserver(observer) }
            observers.removeAll()
            toolbarWindow = nil
        }

        func scheduleAlignment() {
            guard !scheduled else { return }
            scheduled = true
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                scheduled = false
                guard let window = toolbarWindow ?? window, let toolbar = window.toolbar,
                      let actions = toolbar.items.first(where: { item in
                          item.view.map { self.isDescendant(of: $0) } ?? false
                      }) else { return }
                WorkspaceToolbarAlignment.pin(actions, in: toolbar)
                updateTabViewport(in: toolbar, before: actions, window: window)
            }
        }

        private func updateTabViewport(in toolbar: NSToolbar, before actions: NSToolbarItem, window: NSWindow) {
            guard let onTabViewportWidth, let actionsView = actions.view else { return }
            window.contentView?.superview?.layoutSubtreeIfNeeded()
            let actionsFrame = actionsView.convert(actionsView.bounds, to: nil)
            let rightGap = window.frame.width - actionsFrame.maxX
            if actionsView.window === window, (0...32).contains(rightGap) { trailingInset = rightGap }
            for (index, item) in toolbar.items.enumerated() {
                guard let view = item.view, let viewport = WorkspaceTabViewport.find(in: view),
                      viewport.bounds.width > 0 else { continue }
                WorkspaceToolbarAlignment.keepFileTabsNeutral(item, in: toolbar)
                let precedingEdge = toolbar.items.prefix(index).compactMap { item -> CGFloat? in
                    guard let view = item.view, view.window === window else { return nil }
                    return view.convert(view.bounds, to: nil).maxX
                }.max()
                let attached = view.window === window && !view.isHiddenOrHasHiddenAncestor
                let leadingInset: CGFloat
                if attached {
                    leadingInset = view.convert(view.bounds, to: nil).minX
                    lastLeadingInset = leadingInset
                    if let precedingEdge { leadingItemGap = max(0, leadingInset - precedingEdge) }
                } else if let precedingEdge {
                    leadingInset = precedingEdge + leadingItemGap
                } else {
                    leadingInset = lastLeadingInset ?? 100
                }
                let chromeWidth = max(0, view.bounds.width - viewport.bounds.width)
                // Use window width even when AppKit has temporarily moved an oversized
                // tab item into overflow during a resize; its old frame is then stale.
                var width = max(0, window.frame.width - trailingInset - actionsFrame.width - leadingInset - chromeWidth - 24)
                if !attached && precedingEdge == nil {
                    // Reattach first, then measure the changed sidebar/native controls.
                    width = min(width, max(80, window.frame.width / 6))
                }
                guard width > 0, lastReportedWidth.map({ abs($0 - width) > 0.5 }) ?? true else { return }
                lastReportedWidth = width
                onTabViewportWidth(width)
                return
            }
        }
    }
}

/// Measures the real scroll viewport rather than guessing the width of titlebar controls.
struct WorkspaceTabViewport: NSViewRepresentable {
    final class Marker: NSView {}
    func makeNSView(context: Context) -> Marker { Marker() }
    func updateNSView(_ view: Marker, context: Context) {}

    static func find(in view: NSView) -> Marker? {
        if let marker = view as? Marker { return marker }
        return view.subviews.lazy.compactMap { find(in: $0) }.first
    }
}
