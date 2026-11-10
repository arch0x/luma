import SwiftUI
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    var onOpen: (([URL]) -> Void)?
    var pending: [URL] = []
    var onTerminate: (() async -> Bool)?
    private var terminating = false

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !terminating else { return .terminateLater }
        terminating = true
        Task {
            let allowed = await onTerminate?() ?? true
            if !allowed { terminating = false }
            sender.reply(toApplicationShouldTerminate: allowed)
        }
        return .terminateLater
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NotificationCenter.default.addObserver(self, selector: #selector(textEditingBegan),
                                               name: NSControl.textDidBeginEditingNotification, object: nil)
        AppLocalization.shared.installMenuLocalization()
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func textEditingBegan(_ notification: Notification) {
        guard let field = notification.object as? NSTextField,
              let editor = field.currentEditor() as? NSTextView else { return }
        LumaTheme.apply(to: editor)
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        if let onOpen { onOpen(urls) }
        else { pending.append(contentsOf: urls) }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        sender.windows.first { $0.canBecomeMain }?.makeKeyAndOrderFront(nil)
        return true
    }
}

@main struct LumaApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @ViewState private var workspace: Workspace

    init() {
        let workspace = Workspace()
        _workspace = ViewState(initialValue: workspace)
        AppLocalization.shared.language = workspace.language
    }

    var body: some Scene {
        Window(tr("Luma · 澄览"), id: "workspace") {
            WorkspaceView(workspace: workspace)
                .frame(minWidth: 690, minHeight: 480)
                .preferredColorScheme(workspace.appearance.colorScheme)
                .environment(\.locale, workspace.language.locale)
                .onAppear {
                    delegate.onOpen = { workspace.open($0) }
                    delegate.onTerminate = { await workspace.confirmCloseAll() }
                    workspace.restore()
                    workspace.refreshDirectoriesAutomatically()
                    workspace.open(delegate.pending)
                    delegate.pending.removeAll()
                    let arguments = CommandLine.arguments.dropFirst().filter { !$0.hasPrefix("-") }
                    workspace.open(arguments.map { URL(fileURLWithPath: $0) })
                }
        }
        .defaultSize(width: 1180, height: 780)
        .windowToolbarStyle(.unified(showsTitle: false))
        .commands {
            CommandGroup(replacing: .newItem) {
                Button(tr("打开文件…"), action: workspace.chooseFiles).keyboardShortcut("o")
                Button(tr("打开文件夹…"), action: workspace.chooseFolder).keyboardShortcut("o", modifiers: [.command, .shift])
                Divider()
                Button(tr("打开示例工作区"), action: workspace.openSamples)
            }
            CommandGroup(replacing: .saveItem) {
                Button(tr("保存"), action: workspace.saveActive).keyboardShortcut("s")
                    .disabled(workspace.activeTab.map { !$0.canEdit || $0.isSaving || $0.isRenaming || (!$0.isDirty && !$0.externalChange) } ?? true)
            }
            CommandGroup(after: .textEditing) {
                Button(tr("添加阅读书签"), action: workspace.addReadingBookmark)
                    .keyboardShortcut("d")
                    .disabled(workspace.activeTab.map { $0.kind != .markdown || $0.showSource } ?? true)
            }
            CommandGroup(replacing: .undoRedo) {
                Button(tr("撤销")) { workspace.performUndoShortcut() }
                    .keyboardShortcut("z")
                Button(tr("重做")) { workspace.performUndoShortcut(redo: true) }
                    .keyboardShortcut("z", modifiers: [.command, .shift])
            }
            CommandGroup(replacing: .textEditing) {
                Button(tr("查找…")) { workspace.openFocusedFind() }
                    .keyboardShortcut("f")
                Button(tr("查找下一个")) { workspace.advanceFind(1) }.keyboardShortcut("g").disabled(!workspace.canFindNext)
                Button(tr("查找上一个")) { workspace.advanceFind(-1) }.keyboardShortcut("g", modifiers: [.command, .shift]).disabled(!workspace.canFindPrevious)
            }
            CommandGroup(replacing: .windowSize) {
                Button(tr("关闭标签页")) {
                    if let id = workspace.activeID { workspace.close(id) }
                    else { NSApp.keyWindow?.performClose(nil) }
                }.keyboardShortcut("w")
                Button(tr("下一个标签页")) { workspace.moveTab(1) }.keyboardShortcut(.tab, modifiers: .control)
                Button(tr("上一个标签页")) { workspace.moveTab(-1) }.keyboardShortcut(.tab, modifiers: [.control, .shift])
                Divider()
                Button(tr("刷新目录与当前文件"), action: workspace.refresh).keyboardShortcut("r")
            }
            SidebarCommands()
        }

        Settings {
            SettingsView(workspace: workspace)
                .tint(LumaTheme.accent)
                .accentColor(LumaTheme.accent)
                .preferredColorScheme(workspace.appearance.colorScheme)
                .environment(\.locale, workspace.language.locale)
        }
    }
}

struct SettingsView: View {
    @Bindable var workspace: Workspace

    private enum Page: CaseIterable { case appearance, reading, editing }
    @ViewState private var page = Page.appearance

    var body: some View {
        VStack(spacing: 10) {
            Picker(tr("设置分区"), selection: $page) {
                Text(tr("外观")).tag(Page.appearance)
                Text(tr("阅读")).tag(Page.reading)
                Text(tr("编辑模式")).tag(Page.editing)
            }.pickerStyle(.segmented).labelsHidden()
            Group {
                switch page {
                case .appearance: appearanceSettings
                case .reading: readingSettings
                case .editing: editingSettings
                }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .padding(14).frame(width: 490, height: 445)
        .background(LumaTheme.chrome)
    }

    private var appearanceSettings: some View {
        Form {
            Section(tr("窗口外观")) {
                AppearancePicker(selection: $workspace.appearance)
                    .pickerStyle(.segmented)
            }
            Section(tr("语言 / Language")) {
                Picker(tr("界面语言"), selection: $workspace.language) {
                    ForEach(AppLanguage.allCases, id: \.self) { language in
                        Text(verbatim: language.nativeName).tag(language)
                    }
                }
                Text(tr("切换后立即生效并自动保存，不会修改文件内容。"))
                    .font(.caption).foregroundStyle(LumaTheme.muted)
            }
            Section(tr("关于 Luma")) {
                LabeledContent(tr("版本"), value: "0.9.0")
                Text(tr("文件在本机读取。支持 ⌘S 保存，可在「编辑模式」中开启自动保存。"))
                    .font(.caption).foregroundStyle(LumaTheme.muted)
            }
        }
    }

    private var editingSettings: some View {
        Form {
            Section(tr("文件保存")) {
                Toggle(tr("自动保存"), isOn: $workspace.autoSaveEnabled)
                Text(tr("停止输入约 1 秒后保存所有已打开文本文件的修改。遇到外部冲突或保存失败时暂停，保留草稿供手动处理。"))
                    .font(.caption).foregroundStyle(LumaTheme.muted)
            }
            Section(tr("源码排版")) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(tr("字号"))
                        Spacer()
                        Text("\(Int(workspace.editorFontSize)) pt").monospacedDigit().foregroundStyle(.secondary)
                    }
                    Slider(value: $workspace.editorFontSize, in: EditorTypography.fontSizeRange, step: 1)
                        .accessibilityLabel(tr("编辑模式字号"))
                }
                Text(tr("适用于所有文件的源码编辑区，即时生效并自动保留。"))
                    .font(.caption).foregroundStyle(LumaTheme.muted)
            }
        }
    }

    private var readingSettings: some View {
        Form {
            Section(tr("Markdown 阅读")) {
                Picker(tr("正文字体"), selection: $workspace.markdownFont) {
                    ForEach(MarkdownFont.allCases) { font in Text(font.title).tag(font) }
                }
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(tr("字号"))
                        Spacer()
                        Text("\(Int(workspace.markdownFontSize)) pt").monospacedDigit().foregroundStyle(.secondary)
                    }
                    Slider(value: $workspace.markdownFontSize, in: MarkdownTypography.fontSizeRange, step: 1)
                        .accessibilityLabel(tr("Markdown 正文字号"))
                }
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(tr("行距"))
                        Spacer()
                        Text(tr("\(workspace.markdownLineHeight, specifier: "%.2f") 倍")).monospacedDigit().foregroundStyle(.secondary)
                    }
                    Slider(value: $workspace.markdownLineHeight, in: MarkdownTypography.lineHeightRange, step: 0.05)
                        .accessibilityLabel(tr("Markdown 正文行距"))
                }
                Toggle(tr("正文铺满阅读区"), isOn: $workspace.previewFullWidth)
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(tr("自定义最大宽度"))
                        Spacer()
                        Text("\(Int(workspace.previewMaxWidth)) pt").monospacedDigit().foregroundStyle(.secondary)
                    }
                    Slider(value: $workspace.previewMaxWidth, in: 640...1_600, step: 20)
                        .accessibilityLabel(tr("Markdown 正文最大宽度"))
                }.disabled(workspace.previewFullWidth)
                Text(tr("排版修改即时生效并自动保留。代码保留等宽字体，公式保留数学字体。关闭铺满后可调整正文宽度。"))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
