import SwiftUI
import AppKit
import ReaderCore

struct DocumentView: View {
    @Bindable var tab: DocumentTab
    @Bindable var workspace: Workspace
    @ViewState private var findFocused = false
    @ViewState private var showingInformation = false
    private var reading: MarkdownRenderState { tab.markdownRenderState }

    var body: some View {
        document
    }

    private var document: some View {
        VStack(spacing: 0) {
            if tab.externalChange {
                HStack {
                    Label(tr("磁盘文件已被其他程序修改或删除"), systemImage: "exclamationmark.triangle")
                        .foregroundStyle(LumaTheme.warning)
                    Spacer()
                    Button(tr("重新载入")) { Task { await workspace.reload(tab) } }
                        .buttonStyle(LumaButtonStyle(emphasis: .secondary)).disabled(tab.isSaving)
                }.font(.caption).padding(10).background(LumaTheme.warningSurface)
            }

            if workspace.showFind && (tab.kind.hasSource || tab.kind == .pdf) {
                if tab.kind == .markdown && !tab.showSource {
                    MarkdownFindBar(search: tab.markdownFind, focusRequest: workspace.findFocusRequest) {
                        tab.markdownFind.clear()
                        workspace.showFind = false
                    }
                } else {
                    HStack(spacing: 6) {
                        HStack(spacing: 7) {
                            Image(systemName: "magnifyingglass").foregroundStyle(LumaTheme.muted)
                                .accessibilityHidden(true)
                            SearchTextField(text: $tab.sourceQuery,
                                            placeholder: tab.kind == .pdf ? tr("在 PDF 中查找") : tr("在源码中查找"),
                                            accessibilityLabel: tr("正文搜索"), focusRequest: workspace.findFocusRequest,
                                            onFocusChange: { findFocused = $0 },
                                            onSubmit: { _ in tab.findRequest += 1 },
                                            onCancel: { workspace.showFind = false })
                                .onChange(of: tab.sourceQuery) { _, _ in tab.findRequest += 1 }
                        }.lumaField(focused: findFocused)
                        Button { tab.findRequest += 1 } label: { Image(systemName: "chevron.down") }
                            .help(tr("下一个匹配 ↩")).accessibilityLabel(tr("下一个匹配"))
                        Button {
                            workspace.showFind = false
                            tab.sourceQuery = ""
                        } label: { Image(systemName: "xmark") }.accessibilityLabel(tr("关闭查找"))
                    }.font(.system(size: 12)).buttonStyle(LumaButtonStyle())
                    .padding(.horizontal, 16).padding(.vertical, 6)
                    .background(LumaTheme.chrome)
                    .onExitCommand { workspace.showFind = false }
                }
                LumaRule()
            }

            HStack(spacing: 0) {
                if !hasMarkdownPreviewRail {
                    DocumentReaderRail(tab: tab, workspace: workspace, showingInformation: $showingInformation) {
                        Spacer(minLength: 0)
                    }
                }
                Group {
                    switch tab.state {
                    case .loading:
                        ProgressView(tr("正在读取…")).frame(maxWidth: .infinity, maxHeight: .infinity)
                    case .ready(let content): reader(content)
                    }
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            }.frame(maxWidth: .infinity, maxHeight: .infinity)

        }
        .onAppear {
            if workspace.showFind && tab.kind.hasSource && tab.kind != .markdown { tab.showSource = true }
            if !workspace.showFind { tab.markdownFind.clear() }
        }
        .onChange(of: workspace.showFind) { _, showing in
            if showing && tab.kind.hasSource && tab.kind != .markdown { tab.showSource = true }
            if !showing { tab.sourceQuery = ""; tab.markdownFind.clear() }
        }
        .onChange(of: tab.showSource) { _, source in
            showingInformation = false
            if tab.kind == .markdown {
                let query = source ? tab.markdownFind.query : tab.sourceQuery
                tab.markdownFind.clear(); tab.sourceQuery = ""
                if workspace.showFind {
                    if source { tab.sourceQuery = query; tab.findRequest += 1 }
                    else { tab.markdownFind.setQuery(query) }
                    workspace.findFocusRequest += 1
                }
            } else if !source { workspace.showFind = false }
        }
    }

    private var hasMarkdownPreviewRail: Bool {
        if case .ready(.markdown) = tab.state { return !tab.showSource && !tab.previewPending && tab.previewError == nil }
        return false
    }

    @ViewBuilder private func reader(_ content: LoadedContent) -> some View {
        if let source = tab.draft ?? content.source, tab.showSource || (tab.kind == .text && tab.codeLanguage == nil) {
            SourceReader(text: source, tab: tab, fontSize: workspace.editorFontSize)
        } else if tab.previewPending {
            ProgressView(tr("正在更新预览…")).frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error = tab.previewError {
            VStack(spacing: 16) {
                Image(systemName: "exclamationmark.triangle").font(.largeTitle).foregroundStyle(.secondary)
                Text(tr("暂时无法生成预览")).font(.headline)
                Text(error).font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                Text(tr("源码和未保存的修改仍保留，可以继续编辑或保存。")).font(.caption).foregroundStyle(.secondary)
                Button(tr("返回源码编辑")) { tab.showSource = true }
                    .buttonStyle(LumaButtonStyle(emphasis: .secondary))
            }.padding(32).frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            switch content {
            case .markdown(let source):
                MarkdownPreview(source: source, tab: tab, imageRoot: workspace.imageRoot(for: tab.url),
                                previewWidth: workspace.markdownPreviewWidth, typography: workspace.markdownTypography,
                                state: reading, workspace: workspace, showingInformation: $showingInformation, onOpen: workspace.open)
            case .svg(let source): SVGReader(source: source, tab: tab)
            case .json(let source, _): CodePreview(source: tab.draft ?? source, tab: tab)
            case .table: TableReader(state: tab.tableReading)
            case .text(let text):
                if tab.codeLanguage != nil { CodePreview(source: tab.draft ?? text, tab: tab) }
                else { SourceReader(text: text, tab: tab, fontSize: workspace.editorFontSize) }
            case .failed(let message):
                FilePlaceholder(symbol: "doc.badge.ellipsis", title: tr("暂时无法预览"), message: tab.loadFailure?.localizedDescription ?? message, url: tab.url) {
                    workspace.load(tab)
                }
            case .native:
                switch tab.kind {
                case .pdf: PDFReader(tab: tab)
                case .image: ImageReader(tab: tab)
                default:
                    FilePlaceholder(symbol: "doc", title: tr("暂不支持此格式"), message: tr("此文件无法作为纯文本预览。请在默认应用中打开。"), url: tab.url)
                }
            }
        }
    }
}

/// The workspace owns the window toolbar so document changes cannot remove its actions.
struct DocumentToolbar: View {
    static var width: CGFloat { 3 * 36 + DocumentModeSwitch.width + 3 * 4 }
    @Bindable var tab: DocumentTab
    @Bindable var workspace: Workspace

    var body: some View {
        HStack(spacing: 4) {
            Group {
                if tab.canEdit && (tab.isDirty || tab.externalChange || tab.isSaving) {
                    Button(action: workspace.saveActive) {
                        Image(systemName: "square.and.arrow.down")
                    }
                    .buttonStyle(LumaButtonStyle(emphasis: .primary))
                    .disabled(tab.isSaving || tab.isLoading || tab.isRenaming)
                    .help(tr("保存到原文件 ⌘S")).accessibilityLabel(tr("保存到原文件"))
                } else {
                    Color.clear.accessibilityHidden(true)
                }
            }
            .frame(width: 36, height: 38)

            Group {
                if workspace.canFind {
                    Button(action: workspace.openFind) {
                        Image(systemName: "magnifyingglass")
                    }
                    .buttonStyle(LumaButtonStyle(selected: workspace.showFind))
                    .help(tr("查找 ⌘F")).accessibilityLabel(tr("查找"))
                } else {
                    Color.clear.accessibilityHidden(true)
                }
            }
            .frame(width: 36, height: 38)

            Group {
                if tab.hasPreview {
                    DocumentModeSwitch(showSource: $tab.showSource)
                } else {
                    Color.clear.accessibilityHidden(true)
                }
            }
            .frame(width: DocumentModeSwitch.width, height: 38)

            Button(action: workspace.refresh) { Image(systemName: "arrow.clockwise") }
                .buttonStyle(LumaButtonStyle())
                .frame(width: 36, height: 38)
                .help(tr("刷新目录与当前文件 ⌘R"))
                .accessibilityLabel(tr("刷新目录与当前文件"))
        }
        // Three icon slots, the mode switch, and three gaps stay anchored to the right edge.
        .frame(width: Self.width, height: 38, alignment: .trailing)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(tr("文档工具栏"))
    }

}

struct FilePlaceholder: View {
    let symbol: String
    let title: String
    let message: String
    let url: URL
    var retry: (() -> Void)?

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: symbol).font(.system(size: 40, weight: .ultraLight)).foregroundStyle(.tertiary)
            Text(title).font(.title3.weight(.medium))
            Text(message).font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 400)
            HStack {
                if let retry { Button(tr("重试"), action: retry) }
                Button(tr("在默认应用中打开")) { NSWorkspace.shared.open(url) }
            }.buttonStyle(LumaButtonStyle(emphasis: .secondary)).padding(.top, 6)
        }.padding(36).frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
