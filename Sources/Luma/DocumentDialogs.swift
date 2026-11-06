import AppKit

enum UnsavedChoice { case save, discard, cancel }
enum ConflictChoice { case overwrite, reload, cancel }

enum DocumentDialogs {
    static func unsaved(_ tab: DocumentTab) async -> UnsavedChoice {
        let alert = NSAlert()
        alert.messageText = "要保存对“\(tab.title)”的修改吗？"
        alert.informativeText = "保存会写入原文件。不保存将放弃本次编辑。"
        alert.addButton(withTitle: "保存")
        alert.addButton(withTitle: "不保存")
        alert.addButton(withTitle: "取消").keyEquivalent = "\u{1b}"
        switch alert.runModal() {
        case .alertFirstButtonReturn: return .save
        case .alertSecondButtonReturn: return .discard
        default: return .cancel
        }
    }

    static func conflict(_ tab: DocumentTab) async -> ConflictChoice {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "“\(tab.title)”的磁盘版本已改变"
        alert.informativeText = "文件已被其他程序修改、替换或删除。取消会保留当前编辑；重新载入将放弃当前编辑；覆盖会将当前编辑写入磁盘。"
        alert.addButton(withTitle: "取消").keyEquivalent = "\u{1b}"
        alert.addButton(withTitle: "重新载入磁盘版本")
        alert.addButton(withTitle: "覆盖磁盘文件")
        switch alert.runModal() {
        case .alertSecondButtonReturn: return .reload
        case .alertThirdButtonReturn: return .overwrite
        default: return .cancel
        }
    }
}
