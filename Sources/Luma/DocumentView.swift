import SwiftUI
import AppKit
import ReaderCore

struct DocumentView: View {
    @Bindable var tab: DocumentTab
    @Bindable var workspace: Workspace
    @FocusState private var findFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text(tab.url.deletingLastPathComponent().lastPathComponent).foregroundStyle(.tertiary)
                Image(systemName: "chevron.right").font(.system(size: 8)).foregroundStyle(.quaternary)
                Text(tab.title).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                if tab.isDirty { Text("未保存").foregroundStyle(LumaTheme.accent) }
                Spacer()
                if tab.canEdit && (tab.isDirty || tab.externalChange || tab.isSaving) {
                    Button(tab.isSaving ? "正在保存…" : "保存", action: workspace.saveActive)
                        .disabled(tab.isSaving || tab.isLoading || tab.isRenaming)
                        .help("保存到原文件 ⌘S")
                        .accessibilityLabel("保存到原文件")
                }
                if tab.hasPreview {
                    Picker("文档视图", selection: $tab.showSource) {
                        Text("预览").tag(false)
                        Text("源码").tag(true)
                    }.pickerStyle(.segmented).labelsHidden().frame(width: 118).controlSize(.small)
                        .help("切换预览与源码编辑")
                }
                Text(tab.formatLabel)
                    .font(.system(size: 9, weight: .medium, design: .monospaced)).foregroundStyle(.secondary)
                    .padding(.horizontal, 7).padding(.vertical, 4)
                    .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 4))
            }.font(.system(size: 11)).padding(.horizontal, 22).frame(height: 48)
            Divider().opacity(0.5)

            if tab.externalChange {
                HStack {
                    Label("磁盘文件已被其他程序修改或删除", systemImage: "exclamationmark.triangle")
                    Spacer()
                    Button("重新载入") { Task { await workspace.reload(tab) } }.disabled(tab.isSaving)
                }.font(.caption).padding(10).background(Color.orange.opacity(0.1))
            }

            if workspace.showFind && (tab.kind.hasSource || tab.kind == .pdf) {
                if tab.kind == .markdown && !tab.showSource {
                    MarkdownFindBar(search: tab.markdownFind, focusRequest: workspace.findFocusRequest) {
                        tab.markdownFind.clear()
                        workspace.showFind = false
                    }
                } else {
                    HStack(spacing: 10) {
                        Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                        TextField(tab.kind == .pdf ? "在 PDF 中查找" : "在源码中查找", text: $tab.sourceQuery)
                            .textFieldStyle(.plain).focused($findFocused)
                            .onSubmit { tab.findRequest += 1 }
                            .onChange(of: tab.sourceQuery) { _, _ in tab.findRequest += 1 }
                        Button { tab.findRequest += 1 } label: { Image(systemName: "chevron.down") }.help("下一个匹配 ↩")
                        Button {
                            workspace.showFind = false
                            tab.sourceQuery = ""
                        } label: { Image(systemName: "xmark") }.accessibilityLabel("关闭查找")
                    }.font(.system(size: 12)).buttonStyle(.plain).padding(.horizontal, 22).frame(height: 38)
                    .background(.quaternary.opacity(0.25))
                    .onAppear { findFocused = true }
                    .onChange(of: workspace.findFocusRequest) { _, _ in findFocused = true }
                    .onExitCommand { workspace.showFind = false }
                }
                Divider()
            }

            Group {
                switch tab.state {
                case .loading:
                    ProgressView("正在读取…").frame(maxWidth: .infinity, maxHeight: .infinity)
                case .ready(let content): reader(content)
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider().opacity(0.5)
            HStack(spacing: 6) {
                Circle().fill(LumaTheme.accent.opacity(0.6)).frame(width: 4, height: 4)
                Text(tab.isSaving ? "正在保存…" : tab.canEdit ? (tab.isDirty ? "未保存 · ⌘S 保存" : "已保存") : "只读")
                if let text = tab.draft {
                    Text("·").foregroundStyle(.quaternary)
                    Text("\(text.utf8.count.formatted()) 字节 · UTF-8")
                }
                Spacer()
                Text(tab.url.path).lineLimit(1).truncationMode(.middle)
            }.font(.system(size: 10)).foregroundStyle(.tertiary).padding(.horizontal, 18).frame(height: 28)
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

    @ViewBuilder private func reader(_ content: LoadedContent) -> some View {
        if let source = tab.draft ?? content.source, tab.showSource || (tab.kind == .text && tab.codeLanguage == nil) {
            SourceView(text: source, tab: tab, fontSize: workspace.editorFontSize)
        } else if tab.previewPending {
            ProgressView("正在更新预览…").frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error = tab.previewError {
            VStack(spacing: 16) {
                Image(systemName: "exclamationmark.triangle").font(.largeTitle).foregroundStyle(.secondary)
                Text("暂时无法生成预览").font(.headline)
                Text(error).font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                Text("源码和未保存的修改仍保留，可以继续编辑或保存。").font(.caption).foregroundStyle(.secondary)
                Button("返回源码编辑") { tab.showSource = true }
            }.padding(32).frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            switch content {
            case .markdown(let source): MarkdownPreview(source: source, tab: tab, imageRoot: workspace.imageRoot(for: tab.url), previewWidth: workspace.markdownPreviewWidth, typography: workspace.markdownTypography, onOpen: workspace.open)
            case .json(let source, _): CodePreview(source: tab.draft ?? source, tab: tab)
            case .table(_, let table): TableReader(table: table)
            case .text(let text):
                if tab.codeLanguage != nil { CodePreview(source: tab.draft ?? text, tab: tab) }
                else { SourceView(text: text, tab: tab, fontSize: workspace.editorFontSize) }
            case .failed(let message):
                FilePlaceholder(symbol: "doc.badge.ellipsis", title: "暂时无法预览", message: message, url: tab.url) {
                    workspace.load(tab)
                }
            case .native:
                switch tab.kind {
                case .pdf: PDFReader(tab: tab)
                case .image: ImageReader(tab: tab)
                default:
                    FilePlaceholder(symbol: "doc", title: "这个格式还在路上", message: "当前版本还不支持此文件的预览。", url: tab.url)
                }
            }
        }
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
                if let retry { Button("重试", action: retry) }
                Button("在默认应用中打开") { NSWorkspace.shared.open(url) }
            }.padding(.top, 6)
        }.padding(36).frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct TableReader: View {
    let table: CSVDocument
    var body: some View {
        if table.rows.isEmpty {
            ContentUnavailableView("空表格", systemImage: "tablecells", description: Text("这个文件没有可显示的数据。"))
        } else {
            VStack(alignment: .leading, spacing: 0) {
                Text("\(table.rows.count.formatted()) 行 · \(table.columnCount) 列 · 第一行为表头")
                    .font(.caption).foregroundStyle(.secondary).padding(16)
                ScrollView([.horizontal, .vertical]) {
                    LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                        Section {
                            ForEach(1..<table.rows.count, id: \.self) { index in
                                tableRow(table.rows[index], index: index, header: false)
                            }
                        } header: {
                            tableRow(table.rows[0], index: 0, header: true)
                        }
                    }.padding(.horizontal, 16).padding(.bottom, 16)
                }
            }
        }
    }

    private func tableRow(_ row: [String], index: Int, header: Bool) -> some View {
        HStack(spacing: 0) {
            Text(header ? "#" : "\(index)").font(.system(size: 10, design: .monospaced)).foregroundStyle(.tertiary).frame(width: 42, alignment: .trailing).padding(.trailing, 12)
            ForEach(0..<table.columnCount, id: \.self) { column in
                Text(column < row.count ? row[column] : "")
                    .font(.system(size: 12, weight: header ? .semibold : .regular))
                    .textSelection(.enabled).lineLimit(4)
                    .frame(width: 170, alignment: .leading).padding(.horizontal, 12).padding(.vertical, 11)
            }
        }
        .frame(minHeight: 38)
        .background(header ? Color(nsColor: .controlBackgroundColor) : index.isMultiple(of: 2) ? Color.primary.opacity(0.025) : Color(nsColor: .textBackgroundColor))
        .overlay(alignment: .bottom) { Divider().opacity(0.4) }
    }
}
