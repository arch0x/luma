import AppKit
import SwiftUI
import WebKit
import Testing
import ReaderCore
@testable import Luma

@MainActor @Suite(.serialized) struct LanguageTests {
    @Test func languageChoiceAppliesImmediatelyAndSurvivesRecreation() throws {
        let domain = "local.luma.language-tests.\(UUID())"
        let preferences = try #require(UserDefaults(suiteName: domain))
        let previous = AppLocalization.shared.language
        defer { preferences.removePersistentDomain(forName: domain); AppLocalization.shared.language = previous }
        let workspace = Workspace(preferences: preferences)
        #expect(workspace.language == .english)
        #expect(workspace.language.nativeName == "English")
        #expect(AppLanguage.simplifiedChinese.nativeName == "简体中文")
        workspace.showNotice("正在移动“\("中文文件.txt")”…")
        workspace.language = .english
        #expect(workspace.notice == "Moving “中文文件.txt”…")
        #expect(tr("保存") == "Save")
        #expect(AppAppearance.light.title == "Light")
        #expect(trKey(TableReadingState.WidthMode.comfortable.rawValue) == "Comfortable Columns")
        #expect(ReaderError.notUTF8.errorDescription?.contains("UTF-8 text") == true)
        #expect(Workspace(preferences: preferences).language == .english)
        #expect(preferences.stringArray(forKey: "AppleLanguages") == ["en"])
        workspace.language = .simplifiedChinese
        #expect(tr("保存") == "保存")
        #expect(Workspace(preferences: preferences).language == .simplifiedChinese)
        preferences.set("unknown", forKey: "appLanguage")
        #expect(Workspace(preferences: preferences).language == .english)
    }

    @Test func changingLanguageKeepsOpenDraftSelectionUndoAndFolderState() async throws {
        _ = NSApplication.shared
        let domain = "local.luma.language-draft.\(UUID())"
        let preferences = try #require(UserDefaults(suiteName: domain))
        let previous = AppLocalization.shared.language
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer {
            preferences.removePersistentDomain(forName: domain); AppLocalization.shared.language = previous
            try? FileManager.default.removeItem(at: directory)
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent("中文文件.txt")
        try "原文🙂".write(to: file, atomically: true, encoding: .utf8)
        let workspace = Workspace(preferences: preferences)
        workspace.addFolder(directory); workspace.open([file])
        let tab = try #require(workspace.activeTab)
        await tab.loadTask?.value
        let editor = tab.sourceEditor()
        editor.textView.insertText(" draft", replacementRange: NSRange(location: ("原文🙂" as NSString).length, length: 0))
        editor.textView.breakUndoCoalescing()
        let selection = NSRange(location: 0, length: 2)
        editor.textView.setSelectedRange(selection)
        let undo = editor.textView.undoManager, expanded = workspace.expanded, draft = tab.draft
        workspace.language = .english
        #expect(workspace.activeTab === tab && workspace.tabs.count == 1 && workspace.expanded == expanded)
        #expect(tab.title == "中文文件.txt" && tab.draft == draft && tab.isDirty)
        #expect(tab.sourceEditor() === editor && editor.textView.selectedRange() == selection)
        #expect(editor.textView.undoManager === undo && tab.canUndo)
        #expect(try String(contentsOf: file, encoding: .utf8) == "原文🙂")
        workspace.language = .simplifiedChinese
        editor.textView.undoManager?.undo()
        #expect(tab.draft == "原文🙂" && !tab.isDirty)
    }

    @Test func nativeMenusTranslateControlsButNotDocumentTitlesOrShortcuts() {
        let previous = AppLocalization.shared.language
        defer { AppLocalization.shared.language = previous }
        let menu = NSMenu()
        let file = NSMenuItem(title: "文件", action: nil, keyEquivalent: "")
        let submenu = NSMenu(title: "文件")
        let document = NSMenuItem(title: "文件", action: Selector(("openDocument:")), keyEquivalent: "")
        let copy = NSMenuItem(title: "复制", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        submenu.addItem(document); submenu.addItem(copy); file.submenu = submenu; menu.addItem(file)
        AppLocalization.shared.language = .english
        AppLocalization.shared.localize(menu: menu)
        #expect(file.title == "File" && copy.title == "Copy")
        #expect(document.title == "文件" && copy.keyEquivalent == "c")
        AppLocalization.shared.language = .simplifiedChinese
        AppLocalization.shared.localize(menu: menu)
        #expect(file.title == "文件" && copy.title == "复制")
    }

    @Test func previewSwitchesItsControlsWithoutTranslatingDocumentOrLosingSection() async throws {
        _ = NSApplication.shared
        let source = "# 中文标题\n\n" + String(repeating: "原文段落保持不变。\n\n", count: 12) + "\n## 后半段\n\n```swift\nlet title = \"中文内容\"\n```\n\n| 数据 | 值 |\n| --- | --- |\n| 原样 | 42 |\n" + String(repeating: "继续阅读。\n\n", count: 15)
        let tab = DocumentTab(url: URL(fileURLWithPath: "/tmp/language.md"))
        tab.draft = source; tab.savedText = source
        let state = MarkdownRenderState()
        let coordinator = MarkdownWebView.Coordinator(source: source, tab: tab, dark: false, state: state, onOpen: { _ in })
        let view = MarkdownWebView.makeWebView(coordinator: coordinator)
        view.frame = NSRect(x: 0, y: 0, width: 720, height: 600)
        defer { MarkdownWebView.dismantleNSView(view, coordinator: coordinator) }
        func waitFor(_ condition: () async throws -> Bool) async throws {
            let deadline = ContinuousClock.now + .seconds(20)
            while ContinuousClock.now < deadline {
                if try await condition() { return }
                try await Task.sleep(for: .milliseconds(20))
            }
            try #require(try await condition(), "Localized preview did not settle")
        }
        try await waitFor { !state.loading && state.error == nil }
        _ = try await view.evaluateJavaScript("window.luma.navigateToHeading('后半段')")
        coordinator.language = .english; coordinator.renderIfNeeded()
        try await waitFor {
            guard !state.loading else { return false }
            return try await view.evaluateJavaScript("document.querySelector('.code-toolbar button').textContent === 'Copy Code'") as? Bool == true
        }
        #expect(try await view.evaluateJavaScript("document.documentElement.lang") as? String == "en")
        #expect(try await view.evaluateJavaScript("window.luma.getReadingPosition().headingID") as? String == "后半段")
        #expect(try await view.evaluateJavaScript("document.querySelector('h1').textContent") as? String == "中文标题")
        #expect(try await view.evaluateJavaScript("document.querySelector('pre code').textContent") as? String == "let title = \"中文内容\"")
        #expect(try await view.evaluateJavaScript("document.querySelector('.table-scroll button').textContent") as? String == "Expand Table")
        #expect(tab.draft == source && !tab.isDirty)
        coordinator.language = .simplifiedChinese; coordinator.renderIfNeeded()
        try await waitFor {
            guard !state.loading else { return false }
            return try await view.evaluateJavaScript("document.querySelector('.code-toolbar button').textContent === '复制代码'") as? Bool == true
        }
    }

    @Test(arguments: [false, true])
    func englishSettingsAndWorkspaceFitAndRender(dark: Bool) async throws {
        _ = NSApplication.shared
        let domain = "local.luma.language-layout.\(UUID())"
        let preferences = try #require(UserDefaults(suiteName: domain))
        let previous = AppLocalization.shared.language
        defer { preferences.removePersistentDomain(forName: domain); AppLocalization.shared.language = previous }
        let workspace = Workspace(preferences: preferences); workspace.language = .english
        let host = NSHostingView(rootView: SettingsView(workspace: workspace).environment(\.locale, workspace.language.locale)
            .environment(\.colorScheme, dark ? .dark : .light))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 490, height: 445), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua); window.contentView = host
        defer { window.contentView = nil; window.close() }
        host.layoutSubtreeIfNeeded(); try await Task.sleep(for: .milliseconds(100))
        #expect(host.fittingSize.width <= 490)
        if let path = ProcessInfo.processInfo.environment["LUMA_LANGUAGE_PREVIEW_DIR"], let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) {
            host.cacheDisplay(in: host.bounds, to: bitmap)
            let folder = URL(fileURLWithPath: path)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try #require(bitmap.representation(using: .png, properties: [:])).write(to: folder.appendingPathComponent(dark ? "settings-english-dark.png" : "settings-english-light.png"))
        }
        let samples = try #require(workspace.samplesURL)
        workspace.addFolder(samples)
        workspace.open([samples.appendingPathComponent("Welcome.md"), samples.appendingPathComponent("ReadingList.csv")])
        for tab in workspace.tabs { await tab.loadTask?.value }
        let controller = NSHostingController(rootView: WorkspaceView(workspace: workspace).environment(\.colorScheme, dark ? .dark : .light))
        let readerWindow = NSWindow(contentViewController: controller)
        readerWindow.isReleasedWhenClosed = false
        readerWindow.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        readerWindow.setContentSize(NSSize(width: 690, height: 510))
        defer { readerWindow.toolbar = nil; readerWindow.delegate = nil; readerWindow.close() }
        controller.view.layoutSubtreeIfNeeded(); try await Task.sleep(for: .milliseconds(150))
        #expect(controller.view.bounds.width <= 690)
        if let path = ProcessInfo.processInfo.environment["LUMA_LANGUAGE_PREVIEW_DIR"], let frame = readerWindow.contentView?.superview,
           let bitmap = frame.bitmapImageRepForCachingDisplay(in: frame.bounds) {
            frame.layoutSubtreeIfNeeded(); frame.cacheDisplay(in: frame.bounds, to: bitmap)
            let folder = URL(fileURLWithPath: path)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try #require(bitmap.representation(using: .png, properties: [:])).write(to: folder.appendingPathComponent(dark ? "workspace-english-dark.png" : "workspace-english-light.png"))
        }

    }
}
