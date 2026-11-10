import AppKit
import Foundation
import Observation
import ReaderCore

typealias AppLanguage = InterfaceLanguage

@Observable final class AppLocalization {
    static let shared = AppLocalization()
    var language = AppLanguage.english {
        didSet {
            ReaderLocalization.language = language
            updateNativeMenus()
            DispatchQueue.main.async { [weak self] in self?.updateNativeMenus() }
        }
    }
    private var menuObserver: NSObjectProtocol?
    func installMenuLocalization() {
        guard menuObserver == nil else { return }
        menuObserver = NotificationCenter.default.addObserver(forName: NSMenu.didBeginTrackingNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateNativeMenus() }
        }
        updateNativeMenus()
    }
    func updateNativeMenus() {
        guard let menu = NSApp?.mainMenu else { return }
        localize(menu: menu)
    }
    func localize(menu: NSMenu) {
        let titles = ["文件": "File", "编辑": "Edit", "显示": "View", "窗口": "Window", "帮助": "Help", "服务": "Services"]
        let actions = ["hide:": "隐藏 Luma", "hideOtherApplications:": "隐藏其他", "unhideAllApplications:": "显示全部",
                       "terminate:": "退出 Luma", "orderFrontStandardAboutPanel:": "关于 Luma", "showSettingsWindow:": "设置…",
                       "showPreferencesWindow:": "设置…", "cut:": "剪切", "copy:": "复制", "paste:": "粘贴",
                       "pasteAsPlainText:": "粘贴并匹配样式", "selectAll:": "全选", "undo:": "撤销", "redo:": "重做",
                       "performClose:": "关闭窗口", "performMiniaturize:": "最小化", "performZoom:": "缩放",
                       "arrangeInFront:": "前置所有窗口", "toggleSidebar:": "显示或隐藏侧栏", "toggleFullScreen:": "切换全屏"]
        for item in menu.items {
            if item.submenu != nil, let key = titles.first(where: { item.title == $0.key || item.title == $0.value })?.key {
                item.title = ReaderLocalization.text(key: key, language: language)
            }
            if let selector = item.action.map(NSStringFromSelector), let key = actions[selector] {
                item.title = ReaderLocalization.text(key: key, language: language)
            }
            if let submenu = item.submenu { localize(menu: submenu) }
        }
    }
}

func tr(_ message: InterfaceMessage) -> String {
    ReaderLocalization.text(message, language: AppLocalization.shared.language)
}
func trKey(_ key: String) -> String {
    ReaderLocalization.text(key: key, language: AppLocalization.shared.language)
}

nonisolated func readerText(_ message: InterfaceMessage) -> String { ReaderLocalization.text(message) }
