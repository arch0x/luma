import AppKit
import SwiftUI
import ReaderCore

struct SidebarRowLabel: View {
    let entry: FileEntry
    let depth: Int
    let expanded: Bool
    let selected: Bool
    var colorScheme: ColorScheme = .light
    var body: some View {
        HStack(spacing: 6) {
            Group {
                if entry.isDirectory {
                    Image(systemName: expanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 8, weight: .semibold)).foregroundStyle(LumaTheme.muted)
                } else { Color.clear }
            }.frame(width: 10)
            Image(systemName: entry.isDirectory ? "folder" : entry.kind.symbol)
                .font(.system(size: 12)).foregroundStyle(entry.isDirectory || selected ? LumaTheme.accent : LumaTheme.muted).frame(width: 15)
            Text(entry.name).font(.system(size: 12, weight: depth == 0 || selected ? .medium : .regular))
                .foregroundStyle(LumaTheme.ink)
                .lineLimit(1).truncationMode(.middle)
            Spacer(minLength: 0)
        }
        .padding(.leading, CGFloat(min(depth, 16)) * 12 + 6).padding(.trailing, 8).frame(height: 30)
        .background(selected ? LumaTheme.selected : .clear, in: RoundedRectangle(cornerRadius: LumaTheme.controlRadius))
        .environment(\.colorScheme, colorScheme)
    }
}

struct SidebarNativeRow: NSViewRepresentable {
    @Environment(\.colorScheme) private var colorScheme
    let entry: FileEntry
    let depth: Int
    let workspace: Workspace
    let isWorkspaceRoot: Bool
    let isExpanded: Bool
    let isSelected: Bool
    func makeNSView(context: Context) -> SidebarRowView { SidebarRowView(entry: entry, workspace: workspace) }
    func updateNSView(_ view: SidebarRowView, context: Context) {
        view.entry = entry
        view.isWorkspaceRoot = isWorkspaceRoot
        view.toolTip = entry.url.path
        view.label.appearance = NSAppearance(named: colorScheme == .dark ? .darkAqua : .aqua)
        view.label.rootView = SidebarRowLabel(entry: entry, depth: depth, expanded: isExpanded, selected: isSelected, colorScheme: colorScheme)
        view.setAccessibilityLabel(entry.isDirectory ? "文件夹 \(entry.name)" : entry.name)
    }
}

/// Owns the mouse sequence itself so a SwiftUI Button cannot consume drag initiation.
final class SidebarRowView: NSView, NSDraggingSource {
    static var pasteboardType: NSPasteboard.PasteboardType { .init(SidebarDragItem.contentType.identifier) }
    var entry: FileEntry
    let workspace: Workspace
    var isWorkspaceRoot = false
    let label: NSHostingView<SidebarRowLabel>
    private var mouseDownEvent: NSEvent?
    private var didDrag = false
    private var dragID: UUID?
    private(set) var isDropTarget = false { didSet { needsDisplay = true } }
    // Tests observe the real mouse-to-session boundary without moving the user's physical pointer.
    var startSession: (([NSDraggingItem], NSEvent) -> Void)?
    private(set) var dropTask: Task<Void, Never>?

    init(entry: FileEntry, workspace: Workspace) {
        self.entry = entry
        self.workspace = workspace
        label = NSHostingView(rootView: SidebarRowLabel(entry: entry, depth: 0, expanded: false, selected: false))
        super.init(frame: NSRect(x: 0, y: 0, width: 240, height: 30))
        label.frame = bounds
        label.autoresizingMask = [.width, .height]
        addSubview(label)
        focusRingType = .exterior
        registerForDraggedTypes([Self.pasteboardType])
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel(entry.name)
    }
    required init?(coder: NSCoder) { nil }
    override var isOpaque: Bool { false }
    override var acceptsFirstResponder: Bool { true }
    override var intrinsicContentSize: NSSize { NSSize(width: NSView.noIntrinsicMetric, height: 30) }
    override func hitTest(_ point: NSPoint) -> NSView? { super.hitTest(point) == nil ? nil : self }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        if isDropTarget {
            let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 6, yRadius: 6)
            LumaTheme.nativeAccent.withAlphaComponent(0.14).setFill(); path.fill()
            LumaTheme.nativeAccent.withAlphaComponent(0.7).setStroke(); path.lineWidth = 1; path.stroke()
        }
    }

    override var focusRingMaskBounds: NSRect { bounds.insetBy(dx: 2, dy: 2) }
    override func drawFocusRingMask() {
        NSBezierPath(roundedRect: focusRingMaskBounds, xRadius: 5, yRadius: 5).fill()
    }
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        let dark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        label.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        label.rootView.colorScheme = dark ? .dark : .light
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        if event.modifierFlags.contains(.control) { rightMouseDown(with: event); return }
        window?.makeFirstResponder(self)
        mouseDownEvent = event
        didDrag = false
    }
    override func mouseDragged(with event: NSEvent) {
        guard let down = mouseDownEvent, !didDrag,
              hypot(event.locationInWindow.x - down.locationInWindow.x, event.locationInWindow.y - down.locationInWindow.y) >= 4 else { return }
        didDrag = true
        guard let item = workspace.beginSidebarDrag(for: entry), let data = try? JSONEncoder().encode(item) else { return }
        let writer = NSPasteboardItem()
        guard writer.setData(data, forType: Self.pasteboardType) else { workspace.draggedItem = nil; return }
        let dragging = NSDraggingItem(pasteboardWriter: writer)
        dragging.setDraggingFrame(bounds, contents: dragImage())
        dragID = item.id
        if let startSession { startSession([dragging], event) }
        else {
            let session = beginDraggingSession(with: [dragging], event: event, source: self)
            session.animatesToStartingPositionsOnCancelOrFail = true
        }
    }
    override func mouseUp(with event: NSEvent) {
        defer { mouseDownEvent = nil }
        guard mouseDownEvent != nil, !didDrag, bounds.contains(convert(event.locationInWindow, from: nil)) else { return }
        activate()
    }
    override func keyDown(with event: NSEvent) {
        if [36, 49, 76].contains(event.keyCode) { activate() }
        else { super.keyDown(with: event) }
    }
    override func accessibilityPerformPress() -> Bool { activate(); return true }
    private func activate() {
        if entry.isDirectory { workspace.toggleDirectory(entry.url) }
        else { workspace.open([entry.url]) }
    }
    private func dragImage() -> NSImage {
        if canDraw, let bitmap = bitmapImageRepForCachingDisplay(in: bounds) {
            cacheDisplay(in: bounds, to: bitmap)
            let image = NSImage(size: bounds.size); image.addRepresentation(bitmap); return image
        }
        let image = NSImage(size: bounds.size)
        image.lockFocus()
        (entry.name as NSString).draw(at: NSPoint(x: 8, y: 8), withAttributes: [.font: NSFont.systemFont(ofSize: 12), .foregroundColor: NSColor.labelColor])
        image.unlockFocus()
        return image
    }
    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        context == .withinApplication ? .move : []
    }
    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        finishDrag(operation: operation)
    }
    func finishDrag(operation: NSDragOperation) {
        mouseDownEvent = nil
        if operation != .move, workspace.draggedItem?.id == dragID { workspace.draggedItem = nil }
    }

    private func acceptedItem(_ pasteboard: NSPasteboard) -> SidebarDragItem? {
        guard entry.isDirectory, let data = pasteboard.data(forType: Self.pasteboardType),
              let item = try? JSONDecoder().decode(SidebarDragItem.self, from: data),
              workspace.draggedItem == item, workspace.canMove(item, into: entry.url) else { return nil }
        return item
    }
    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        isDropTarget = acceptedItem(sender.draggingPasteboard) != nil
        return isDropTarget ? .move : []
    }
    override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation { draggingEntered(sender) }
    override func draggingExited(_ sender: (any NSDraggingInfo)?) { isDropTarget = false }
    override func wantsPeriodicDraggingUpdates() -> Bool { false }
    override func prepareForDragOperation(_ sender: any NSDraggingInfo) -> Bool { acceptedItem(sender.draggingPasteboard) != nil }
    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        isDropTarget = false
        guard let item = acceptedItem(sender.draggingPasteboard) else { return false }
        let folder = entry.url
        dropTask = Task { _ = await workspace.receiveDrop(item, into: folder) }
        return true
    }
    override func concludeDragOperation(_ sender: (any NSDraggingInfo)?) { isDropTarget = false }

    private enum MenuAction: Int { case newFile, newFolder, rename, reveal, refresh, removeRoot, trash }
    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = NSMenu()
        func add(_ title: String, _ action: MenuAction, symbol: String, enabled: Bool = true) {
            let item = NSMenuItem(title: title, action: #selector(performMenuAction(_:)), keyEquivalent: "")
            item.target = self; item.tag = action.rawValue; item.isEnabled = enabled
            item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
            menu.addItem(item)
        }
        menu.autoenablesItems = false
        if entry.isDirectory {
            add("新增文件…", .newFile, symbol: "doc.badge.plus", enabled: !workspace.isMutatingFiles)
            add("新增文件夹…", .newFolder, symbol: "folder.badge.plus", enabled: !workspace.isMutatingFiles)
            menu.addItem(.separator())
        }
        add("重命名…", .rename, symbol: "pencil", enabled: !workspace.isMutatingFiles)
        add("在 Finder 中显示", .reveal, symbol: "magnifyingglass")
        if entry.isDirectory { add("刷新", .refresh, symbol: "arrow.clockwise") }
        if isWorkspaceRoot { add("从工作区移除", .removeRoot, symbol: "minus.circle") }
        menu.addItem(.separator())
        add("移到废纸篓…", .trash, symbol: "trash", enabled: !workspace.isMutatingFiles)
        return menu
    }
    override func rightMouseDown(with event: NSEvent) {
        mouseDownEvent = nil
        if let menu = menu(for: event) { NSMenu.popUpContextMenu(menu, with: event, for: self) }
    }
    @objc private func performMenuAction(_ sender: NSMenuItem) {
        guard let action = MenuAction(rawValue: sender.tag) else { return }
        switch action {
        case .newFile: workspace.newItemRequest = NewItemRequest(folder: entry.url)
        case .newFolder: workspace.newItemRequest = NewItemRequest(folder: entry.url, kind: .folder)
        case .rename: workspace.renameRequest = entry
        case .reveal: NSWorkspace.shared.activateFileViewerSelecting([entry.url])
        case .refresh: workspace.loadDirectory(entry.url, refresh: true)
        case .removeRoot: workspace.removeFolder(entry.url)
        case .trash: workspace.trashRequest = entry
        }
    }
}
