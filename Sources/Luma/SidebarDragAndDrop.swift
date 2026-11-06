import SwiftUI
import AppKit
import UniformTypeIdentifiers
import ReaderCore

nonisolated struct SidebarDragItem: Codable, Equatable, Sendable {
    static let contentType = UTType(exportedAs: "local.luma.reader.sidebar-item", conformingTo: .data)
    let id: UUID
    let workspaceID: UUID
    let url: URL
    let isDirectory: Bool
}

nonisolated enum WorkspaceMoveError: LocalizedError {
    case outsideWorkspace
    var errorDescription: String? { "只能在当前工作区的文件夹之间移动项目。" }
}

extension Workspace {
    func beginSidebarDrag(for entry: FileEntry) -> SidebarDragItem? {
        guard !isMutatingFiles else { return nil }
        let item = SidebarDragItem(id: UUID(), workspaceID: dragWorkspaceID, url: entry.url, isDirectory: entry.isDirectory)
        draggedItem = item
        return item
    }

    func canMove(_ item: SidebarDragItem, into folder: URL) -> Bool {
        guard !isMutatingFiles, item.workspaceID == dragWorkspaceID else { return false }
        let source = WorkspacePath.item(item.url)
        let target = WorkspacePath.normalized(folder)
        let scope = roots.map(WorkspacePath.normalized)
        guard scope.contains(where: { WorkspacePath.contains($0, source) }),
              scope.contains(where: { WorkspacePath.contains($0, target) }),
              WorkspacePath.normalized(item.url.deletingLastPathComponent()) != target else { return false }
        return !item.isDirectory || !WorkspacePath.contains(source, target)
    }

    @discardableResult func receiveDrop(_ item: SidebarDragItem, into folder: URL) async -> Bool {
        guard item.workspaceID == dragWorkspaceID, draggedItem == item else { return false }
        draggedItem = nil
        notice = "正在移动“\(item.url.lastPathComponent)”…"
        do {
            _ = try await move(FileEntry(url: item.url, isDirectory: item.isDirectory), into: folder)
            notice = nil
            return true
        } catch {
            notice = "无法移动“\(item.url.lastPathComponent)”：\(error.localizedDescription)"
            return false
        }
    }
}

