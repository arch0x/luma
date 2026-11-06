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
    @ViewState private var workspace = Workspace()

    var body: some Scene {
        Window("Luma · 澄览", id: "workspace") {
            WorkspaceView(workspace: workspace)
                .frame(minWidth: 860, minHeight: 560)
                .preferredColorScheme(workspace.appearance.colorScheme)
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
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("打开文件…", action: workspace.chooseFiles).keyboardShortcut("o")
                Button("添加文件夹…", action: workspace.chooseFolder).keyboardShortcut("o", modifiers: [.command, .shift])
                Divider()
                Button("打开示例工作区", action: workspace.openSamples)
            }
            CommandGroup(replacing: .saveItem) {
                Button("保存", action: workspace.saveActive).keyboardShortcut("s")
                    .disabled(workspace.activeTab.map { !$0.canEdit || $0.isSaving || $0.isRenaming || (!$0.isDirty && !$0.externalChange) } ?? true)
            }
            CommandGroup(after: .textEditing) {
                Button("添加阅读书签", action: workspace.addReadingBookmark)
                    .keyboardShortcut("d")
                    .disabled(workspace.activeTab.map { $0.kind != .markdown || $0.showSource } ?? true)
            }
            CommandGroup(replacing: .textEditing) {
                Button("查找…", action: workspace.openFind)
                    .keyboardShortcut("f")
                    .disabled(!workspace.canFind)
                Button("查找下一个") { workspace.advanceFind(1) }.keyboardShortcut("g").disabled(!workspace.canFindNext)
                Button("查找上一个") { workspace.advanceFind(-1) }.keyboardShortcut("g", modifiers: [.command, .shift]).disabled(!workspace.canFindPrevious)
            }
            CommandGroup(replacing: .windowSize) {
                Button("关闭标签页") {
                    if let id = workspace.activeID { workspace.close(id) }
                    else { NSApp.keyWindow?.performClose(nil) }
                }.keyboardShortcut("w")
                Button("下一个标签页") { workspace.moveTab(1) }.keyboardShortcut(.tab, modifiers: .control)
                Button("上一个标签页") { workspace.moveTab(-1) }.keyboardShortcut(.tab, modifiers: [.control, .shift])
                Divider()
                Button("刷新目录与当前文件", action: workspace.refresh).keyboardShortcut("r")
            }
            SidebarCommands()
        }

        Settings {
            SettingsView(workspace: workspace)
                .tint(LumaTheme.accent)
                .accentColor(LumaTheme.accent)
                .preferredColorScheme(workspace.appearance.colorScheme)
        }
    }
}

private struct SettingsView: View {
    @Bindable var workspace: Workspace

    var body: some View {
        Form {
            AppearancePicker(selection: $workspace.appearance)
                .pickerStyle(.segmented)
            Section("编辑模式") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("字号")
                        Spacer()
                        Text("\(Int(workspace.editorFontSize)) pt").monospacedDigit().foregroundStyle(.secondary)
                    }
                    Slider(value: $workspace.editorFontSize, in: EditorTypography.fontSizeRange, step: 1)
                        .accessibilityLabel("编辑模式字号")
                }
                Text("适用于所有文件的源码编辑区，即时生效并自动保留。预览字号独立设置。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Markdown 阅读") {
                Picker("正文字体", selection: $workspace.markdownFont) {
                    ForEach(MarkdownFont.allCases) { font in Text(font.title).tag(font) }
                }
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("字号")
                        Spacer()
                        Text("\(Int(workspace.markdownFontSize)) pt").monospacedDigit().foregroundStyle(.secondary)
                    }
                    Slider(value: $workspace.markdownFontSize, in: MarkdownTypography.fontSizeRange, step: 1)
                        .accessibilityLabel("Markdown 正文字号")
                }
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("行距")
                        Spacer()
                        Text("\(workspace.markdownLineHeight, specifier: "%.2f") 倍").monospacedDigit().foregroundStyle(.secondary)
                    }
                    Slider(value: $workspace.markdownLineHeight, in: MarkdownTypography.lineHeightRange, step: 0.05)
                        .accessibilityLabel("Markdown 正文行距")
                }
                Toggle("正文铺满阅读区", isOn: $workspace.previewFullWidth)
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("自定义最大宽度")
                        Spacer()
                        Text("\(Int(workspace.previewMaxWidth)) pt").monospacedDigit().foregroundStyle(.secondary)
                    }
                    Slider(value: $workspace.previewMaxWidth, in: 640...1_600, step: 20)
                        .accessibilityLabel("Markdown 正文最大宽度")
                }.disabled(workspace.previewFullWidth)
                Text("排版修改即时生效并自动保留。代码保留等宽字体，公式保留数学字体。关闭铺满后可调整正文宽度。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            LabeledContent("版本", value: "0.8.4 · 本地编辑版")
            Text("文件在本机读取。源码支持编辑，按 ⌘S 手动保存到原文件。")
                .font(.caption).foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
        .padding().frame(width: 460, height: 600)
    }
}
