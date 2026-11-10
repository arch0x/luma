import AppKit
import ReaderCore
import Testing
@testable import Luma

@MainActor @Suite(.serialized) struct SidebarInteractionTests {
    @MainActor final class DragInfo: NSObject, NSDraggingInfo {
        var draggingDestinationWindow: NSWindow?
        var draggingSourceOperationMask: NSDragOperation = .move
        var draggingLocation: NSPoint = .zero
        var draggedImageLocation: NSPoint = .zero
        nonisolated var draggedImage: NSImage? { nil }
        let draggingPasteboard: NSPasteboard
        var draggingSource: Any?
        var draggingSequenceNumber = 1
        var draggingFormation: NSDraggingFormation = .none
        var animatesToDestination = false
        var numberOfValidItemsForDrop = 1
        var springLoadingHighlight: NSSpringLoadingHighlight = .none
        @MainActor init(pasteboard: NSPasteboard) { draggingPasteboard = pasteboard }
        func slideDraggedImage(to screenPoint: NSPoint) { }
        override nonisolated func namesOfPromisedFilesDropped(atDestination dropDestination: URL) -> [String]? { nil }
        func enumerateDraggingItems(options enumOpts: NSDraggingItemEnumerationOptions, for view: NSView?, classes classArray: [AnyClass], searchOptions: [NSPasteboard.ReadingOptionKey: Any], using block: @escaping (NSDraggingItem, Int, UnsafeMutablePointer<ObjCBool>) -> Void) { }
        func resetSpringLoading() { }
    }
    let directory: URL
    let preferences: UserDefaults
    let domain = "local.luma.sidebar-interaction.\(UUID().uuidString)"
    init() throws {
        _ = NSApplication.shared
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        preferences = try #require(UserDefaults(suiteName: domain))
    }
    private func clean() {
        try? FileManager.default.removeItem(at: directory)
        preferences.removePersistentDomain(forName: domain)
    }
    private func event(_ type: NSEvent.EventType, x: CGFloat = 20, y: CGFloat = 15) throws -> NSEvent {
        try #require(NSEvent.mouseEvent(with: type, location: NSPoint(x: x, y: y), modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, eventNumber: 1, clickCount: 1, pressure: 1))
    }
    private func window(for view: NSView) -> NSWindow {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 280, height: 30), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = view
        view.layoutSubtreeIfNeeded()
        return window
    }

    @Test(arguments: [false, true])
    func mouseDragStartsNativeSessionAndDropMovesFileOrFolder(folder: Bool) async throws {
        defer { clean() }
        let target = directory.appendingPathComponent(".target", isDirectory: true)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: false)
        let item = directory.appendingPathComponent(folder ? ".source" : ".env", isDirectory: folder)
        if folder { try FileManager.default.createDirectory(at: item, withIntermediateDirectories: false) }
        let file = folder ? item.appendingPathComponent("note.txt") : item
        try "original".write(to: file, atomically: true, encoding: .utf8)
        let workspace = chineseWorkspace(preferences: preferences)
        workspace.roots = [directory]
        workspace.open([file])
        let tab = try #require(workspace.activeTab)
        await tab.loadTask?.value
        tab.edit("draft")
        let sourceView = SidebarRowView(entry: FileEntry(url: item, isDirectory: folder), workspace: workspace)
        let targetView = SidebarRowView(entry: FileEntry(url: target, isDirectory: true), workspace: workspace)
        let sourceWindow = window(for: sourceView), targetWindow = window(for: targetView)
        defer { sourceWindow.close(); targetWindow.close() }
        #expect(sourceView.hitTest(NSPoint(x: 20, y: 15)) === sourceView)
        var draggingItems: [NSDraggingItem] = []
        sourceView.startSession = { items, mouse in
            #expect(mouse.type == .leftMouseDragged)
            draggingItems = items
        }
        sourceView.mouseDown(with: try event(.leftMouseDown))
        sourceView.mouseDragged(with: try event(.leftMouseDragged, x: 22))
        #expect(draggingItems.isEmpty)
        sourceView.mouseDragged(with: try event(.leftMouseDragged, x: 32))
        #expect(draggingItems.count == 1)
        let writer = try #require(draggingItems.first?.item as? NSPasteboardItem)
        let data = try #require(writer.data(forType: SidebarRowView.pasteboardType))
        let board = NSPasteboard(name: .init("local.luma.drag-test.\(UUID().uuidString)"))
        defer { board.clearContents() }
        board.declareTypes([SidebarRowView.pasteboardType], owner: nil)
        #expect(board.setData(data, forType: SidebarRowView.pasteboardType))
        let info = DragInfo(pasteboard: board)
        info.draggingDestinationWindow = targetWindow
        #expect(targetView.draggingEntered(info) == .move && targetView.isDropTarget)
        #expect(targetView.prepareForDragOperation(info))
        #expect(targetView.performDragOperation(info))
        // AppKit ends the source session before the queued disk move completes.
        sourceView.finishDrag(operation: .move)
        await targetView.dropTask?.value
        targetView.concludeDragOperation(info)
        #expect(!targetView.isDropTarget)
        #expect(tab.url.path.contains("/.target/") && tab.draft == "draft" && tab.isDirty)
        #expect(!FileManager.default.fileExists(atPath: item.path))
        #expect(FileManager.default.fileExists(atPath: tab.url.path))
        #expect(await workspace.save(tab))
        #expect(try String(contentsOf: tab.url, encoding: .utf8) == "draft")
        sourceView.mouseUp(with: try event(.leftMouseUp, x: 32))
        #expect(workspace.tabs.count == 1)
    }

    @Test func clickAndCancelledDragDoNotMoveOrAccidentallyOpenFiles() async throws {
        defer { clean() }
        let file = directory.appendingPathComponent("note.txt")
        try "original".write(to: file, atomically: true, encoding: .utf8)
        let workspace = chineseWorkspace(preferences: preferences); workspace.roots = [directory]
        let view = SidebarRowView(entry: FileEntry(url: file, isDirectory: false), workspace: workspace)
        let window = window(for: view); defer { window.close() }
        view.startSession = { _, _ in }
        view.mouseDown(with: try event(.leftMouseDown))
        view.mouseDragged(with: try event(.leftMouseDragged, x: 30))
        #expect(workspace.draggedItem != nil)
        view.finishDrag(operation: [])
        view.mouseUp(with: try event(.leftMouseUp, x: 30))
        #expect(workspace.draggedItem == nil && workspace.tabs.isEmpty)
        view.mouseDown(with: try event(.leftMouseDown))
        view.mouseUp(with: try event(.leftMouseUp))
        #expect(workspace.tabs.count == 1)
        await workspace.activeTab?.loadTask?.value
        #expect(FileManager.default.fileExists(atPath: file.path))
    }

    @Test func nativeContextMenuPreservesCreationRenameAndTrashActions() throws {
        defer { clean() }
        let workspace = chineseWorkspace(preferences: preferences)
        let entry = FileEntry(url: directory, isDirectory: true)
        let view = SidebarRowView(entry: entry, workspace: workspace)
        let menu = try #require(view.menu(for: try event(.rightMouseDown)))
        for title in ["新增文件…", "新增文件夹…", "重命名…", "刷新", "移到废纸篓…"] {
            #expect(menu.items.contains { $0.title == title })
        }
        for title in ["新增文件夹…", "重命名…", "移到废纸篓…"] {
            let item = try #require(menu.items.first { $0.title == title })
            #expect(NSApplication.shared.sendAction(try #require(item.action), to: item.target, from: item))
        }
        #expect(workspace.newItemRequest?.kind == .folder)
        #expect(workspace.renameRequest?.url == directory)
        #expect(workspace.trashRequest?.url == directory)
    }
}
