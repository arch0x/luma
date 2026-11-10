import SwiftUI
import AppKit

struct WorkspaceWindowBridge: NSViewRepresentable {
    let workspace: Workspace
    let hasUnsavedChanges: Bool
    var onTabViewportWidth: ((CGFloat) -> Void)? = nil

    func makeNSView(context: Context) -> WindowAttachment { WindowAttachment(workspace: workspace) }
    func updateNSView(_ view: WindowAttachment, context: Context) {
        view.alignment.onTabViewportWidth = onTabViewportWidth
        view.installIfNeeded()
        view.window?.isDocumentEdited = hasUnsavedChanges
    }
    static func dismantleNSView(_ view: WindowAttachment, coordinator: ()) {
        view.removeFocusMonitor()
    }

    final class WindowAttachment: NSView {
        let guardDelegate: WindowCloseGuard
        private let workspace: Workspace
        let alignment = WorkspaceToolbarAlignment.Anchor()
        private var focusMonitor: Any?
        init(workspace: Workspace) {
            self.workspace = workspace
            guardDelegate = WindowCloseGuard(workspace: workspace)
            super.init(frame: .zero)
        }
        required init?(coder: NSCoder) { nil }
        override func viewWillMove(toWindow newWindow: NSWindow?) {
            if newWindow !== window { removeFocusMonitor() }
            super.viewWillMove(toWindow: newWindow)
        }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            installIfNeeded()
        }
        func installIfNeeded() {
            guard let window else { return }
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.titlebarSeparatorStyle = .none
            window.backgroundColor = LumaTheme.nativePaper
            // Older AppKit can omit the zero-sized anchor inside a SwiftUI toolbar.
            // The content attachment supplies the same alignment from a stable window.
            alignment.track(window)
            if focusMonitor == nil {
                focusMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .keyDown]) { [weak self, weak window] event in
                    if let self, let window, event.window === window {
                        workspace.recordFindFocus(from: event, in: window)
                    }
                    return event
                }
            }
            guard window.delegate !== guardDelegate else { return }
            guardDelegate.original = window.delegate
            window.delegate = guardDelegate
        }

        func removeFocusMonitor() {
            alignment.stopObserving()
            if let focusMonitor { NSEvent.removeMonitor(focusMonitor) }
            focusMonitor = nil
        }
    }
}

struct WorkspaceLibraryRegion: NSViewRepresentable {
    let workspace: Workspace

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        workspace.libraryRegion = view
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {}
}

/// Forward SwiftUI's window callbacks while intercepting the one that can discard edits.
nonisolated final class WindowCloseGuard: NSObject, NSWindowDelegate {
    weak var original: (any NSWindowDelegate)?
    private let workspace: Workspace
    private var checking = false
    private var approved = false
    @MainActor private(set) var closeTask: Task<Void, Never>?

    init(workspace: Workspace) { self.workspace = workspace }

    nonisolated override func responds(to selector: Selector!) -> Bool {
        if super.responds(to: selector) { return true }
        return original?.responds(to: selector) ?? false
    }

    nonisolated override func forwardingTarget(for selector: Selector!) -> Any? {
        original
    }

    @MainActor func windowShouldClose(_ sender: NSWindow) -> Bool {
        if approved {
            guard original?.windowShouldClose?(sender) ?? true else { return false }
            return workspace.commitWindowDiscards()
        }
        guard !checking else { return false }
        checking = true
        closeTask = Task { [weak self, weak sender] in
            guard let self else { return }
            let allowed = await workspace.confirmCloseAll(commitDiscards: false)
            checking = false
            guard allowed, let sender else { return }
            approved = true
            sender.performClose(nil)
            approved = false
        }
        return false
    }
}
