import SwiftUI
import AppKit
import ReaderCore

struct WorkspaceView: View {
    @Bindable var workspace: Workspace
    @ViewState private var visibility = NavigationSplitViewVisibility.all
    @ViewState private var dropTarget = false
    @ViewState private var tabViewportWidth: CGFloat = 120
    @ViewState private var searchFocused = false

    var body: some View {
        NavigationSplitView(columnVisibility: $visibility) {
            sidebar
                .navigationSplitViewColumnWidth(min: 185, ideal: 232, max: 360)
        } detail: {
            VStack(spacing: 0) {
                if let tab = workspace.activeTab {
                    DocumentView(tab: tab, workspace: workspace).id(tab.id)
                } else {
                    WelcomeView(workspace: workspace)
                }
                if let notice = workspace.notice {
                    HStack(spacing: 8) {
                        Image(systemName: "info.circle")
                        Text(notice).font(.caption).lineLimit(3)
                        Spacer()
                        Button { workspace.notice = nil } label: { Image(systemName: "xmark") }
                            .buttonStyle(LumaButtonStyle()).accessibilityLabel("关闭提示")
                    }
                    .padding(.horizontal, 12).padding(.vertical, 6).background(LumaTheme.chrome)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(LumaTheme.paper)
            .overlay {
                if dropTarget {
                    RoundedRectangle(cornerRadius: 12).strokeBorder(LumaTheme.accent, style: StrokeStyle(lineWidth: 2, dash: [8]))
                        .padding(10).allowsHitTesting(false)
                }
            }
        }
        .tint(LumaTheme.accent)
        .accentColor(LumaTheme.accent)
        .foregroundStyle(LumaTheme.ink)
        .sheet(item: $workspace.newItemRequest) { request in
            NewItemSheet(folder: request.folder, kind: request.kind, workspace: workspace)
        }
        .sheet(item: $workspace.renameRequest) { entry in
            RenameSheet(entry: entry, workspace: workspace)
        }
        .confirmationDialog("将“\(workspace.trashRequest?.name ?? "")”移到废纸篓？",
            isPresented: Binding(get: { workspace.trashRequest != nil }, set: { if !$0 { workspace.trashRequest = nil } }),
            titleVisibility: .visible, presenting: workspace.trashRequest) { entry in
                Button("移到废纸篓", role: .destructive) { Task { await workspace.trash(entry) } }
                Button("取消", role: .cancel) { }
            } message: { entry in
                Text(entry.isDirectory ? "文件夹及其全部内容会移到废纸篓，可在 Finder 中恢复。" : "文件会移到废纸篓，可在 Finder 中恢复。")
            }
        .background(WorkspaceWindowBridge(workspace: workspace, hasUnsavedChanges: workspace.tabs.contains { $0.isDirty }))
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            workspace.refreshDirectoriesAutomatically()
            Task { await workspace.checkExternalChanges() }
        }
        .toolbar {
            ToolbarItemGroup(placement: .navigation) {
                if visibility == .detailOnly {
                    openFileButton
                    openFolderButton
                }
            }
            ToolbarItem(id: "openDocumentTabs", placement: .navigation) {
                if !workspace.tabs.isEmpty { openDocumentTabs }
            }
            ToolbarItem(id: "documentActions", placement: .primaryAction) {
                Group {
                    if let tab = workspace.activeTab {
                        DocumentToolbar(tab: tab, workspace: workspace)
                            .fixedSize()
                            .layoutPriority(1)
                    } else {
                        Button(action: workspace.refresh) { Image(systemName: "arrow.clockwise") }
                            .buttonStyle(LumaButtonStyle())
                            .frame(width: 36, height: 38)
                            .help("刷新目录与当前文件 ⌘R")
                            .accessibilityLabel("刷新目录与当前文件")
                    }
                }
                .background(WorkspaceToolbarAlignment(onTabViewportWidth: { width in
                    if abs(tabViewportWidth - width) > 0.5 { tabViewportWidth = width }
                }).frame(width: 0, height: 0))
            }
        }
        .toolbarBackground(.hidden, for: .windowToolbar)
        .dropDestination(for: URL.self) { urls, _ in
            let files = urls.filter(\.isFileURL)
            guard !files.isEmpty else { return false }
            workspace.open(files)
            return true
        } isTargeted: { dropTarget = $0 }
        .onChange(of: workspace.query) { _, _ in workspace.search() }
        .onChange(of: workspace.libraryFindFocusRequest) { _, _ in
            visibility = .all
        }
        .onChange(of: workspace.roots) { _, _ in if !workspace.query.isEmpty { workspace.search() } }
        .onChange(of: workspace.activeID) { _, _ in Task { await workspace.checkExternalChanges() } }
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text("资料库").font(.system(size: 14, weight: .semibold))
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 0)
                HStack(spacing: 2) {
                    openFileButton
                    openFolderButton
                }.buttonStyle(LumaButtonStyle())
            }.padding(.horizontal, 12).padding(.vertical, 8)

            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(LumaTheme.muted).accessibilityHidden(true)
                SearchTextField(text: $workspace.query, placeholder: "搜索文件名",
                                accessibilityLabel: "搜索工作区文件名", focusRequest: workspace.libraryFindFocusRequest,
                                focusOnAppear: false, onFocusChange: { searchFocused = $0 })
                if !workspace.query.isEmpty {
                    Button { workspace.query = ""; workspace.libraryFindFocusRequest += 1 } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.plain).foregroundStyle(LumaTheme.muted).accessibilityLabel("清除搜索")
                }
            }
            .font(.system(size: 12)).lumaField(focused: searchFocused)
            .padding(.horizontal, 12).padding(.bottom, 14)

            VStack(spacing: 0) {
                if workspace.query.isEmpty {
                    sidebarHeading("文件夹", count: workspace.roots.count)
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 2) {
                            if workspace.roots.isEmpty {
                                Text("打开文件夹后，它会出现在这里。")
                                    .font(.caption).foregroundStyle(LumaTheme.muted)
                                    .padding(.horizontal, 8).padding(.vertical, 5)
                            } else {
                                ForEach(workspace.roots, id: \.self) { root in
                                    FileTreeRow(entry: FileEntry(url: root, isDirectory: true), depth: 0, workspace: workspace)
                                }
                            }
                        }.padding(.horizontal, 8).padding(.bottom, 8)
                    }
                } else {
                    sidebarHeading("搜索结果", count: workspace.searchResults.count)
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 2) {
                            searchResults
                        }.padding(.horizontal, 8)
                    }
                }
            }
            LumaRule()
            HStack {
                Image(systemName: "internaldrive").font(.caption)
                Text(workspace.autoSaveEnabled ? "本地文件 · 自动保存" : "本地文件 · 手动保存").font(.system(size: 11))
                Spacer()
                SettingsLink { Image(systemName: "gearshape") }
                    .buttonStyle(LumaButtonStyle()).help("设置 ⌘,").accessibilityLabel("设置")
            }.foregroundStyle(LumaTheme.muted).padding(.horizontal, 12).padding(.vertical, 5)
        }
        .background(LumaTheme.chrome)
        .background(WorkspaceLibraryRegion(workspace: workspace).allowsHitTesting(false))
    }

    private var openFileButton: some View {
        Button(action: workspace.chooseFiles) { Image(systemName: "doc.badge.plus") }
            .accessibilityLabel("打开文件").help("打开文件 ⌘O")
    }

    private var openFolderButton: some View {
        Button(action: workspace.chooseFolder) { Image(systemName: "folder.badge.plus") }
            .accessibilityLabel("打开文件夹").help("打开文件夹 ⇧⌘O")
    }

    @ViewBuilder private var searchResults: some View {
        if let error = workspace.searchError {
            Text(error).font(.caption).foregroundStyle(.secondary).padding(12)
        } else if workspace.searchResults.isEmpty && !workspace.searching {
            Text(workspace.roots.isEmpty ? "请先添加文件夹。" : "没有找到匹配的文件。")
                .font(.callout).foregroundStyle(.secondary).padding(12)
        }
        ForEach(workspace.searchResults) { entry in
            Button { workspace.open([entry.url]) } label: {
                VStack(alignment: .leading, spacing: 3) {
                    Label(entry.name, systemImage: entry.kind.symbol).lineLimit(1)
                    Text(entry.url.deletingLastPathComponent().path).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                }.frame(maxWidth: .infinity, alignment: .leading).padding(8)
            }.buttonStyle(LumaButtonStyle(selected: workspace.activeID == entry.url)).help(entry.url.path)
                .contextMenu { FileItemContextMenu(entry: entry, workspace: workspace) }
        }
        if workspace.searchResults.count == 200 {
            Text("最多显示 200 项，请缩小关键词。")
                .font(.caption).foregroundStyle(.secondary).padding(8)
        }
    }

    private func sidebarHeading(_ title: String, count: Int) -> some View {
        HStack {
            Text(title).font(.system(size: 11, weight: .semibold))
                .accessibilityAddTraits(.isHeader)
            Spacer()
            if workspace.searching && !workspace.query.isEmpty {
                ProgressView().controlSize(.mini)
            } else {
                Text(count.formatted()).font(.caption.monospacedDigit())
            }
        }
        .foregroundStyle(LumaTheme.muted)
        .padding(.horizontal, 8).padding(.vertical, 5)
    }

    private var openDocumentTabs: some View {
        ScrollViewReader { scroll in
            ScrollView(.horizontal) {
                HStack(spacing: 4) {
                    ForEach(workspace.tabs) { tab in
                        openDocumentTab(tab).id(tab.id)
                    }
                }.padding(.horizontal, 3)
            }
            .scrollIndicators(.hidden)
            .onChange(of: workspace.activeID, initial: true) { _, id in
                if let id { scroll.scrollTo(id) }
            }
            .onChange(of: tabViewportWidth) { _, _ in
                if let id = workspace.activeID { scroll.scrollTo(id) }
            }
        }
        .frame(minWidth: 0, idealWidth: tabViewportWidth, maxWidth: tabViewportWidth, alignment: .leading)
        .frame(height: 31)
        .background(WorkspaceTabViewport())
        .accessibilityElement(children: .contain)
        .accessibilityLabel("已打开的文件")
    }

    private func openDocumentTab(_ tab: DocumentTab) -> some View {
        let active = tab.id == workspace.activeID
        return HStack(spacing: 1) {
            Button { workspace.activeID = tab.id } label: {
                HStack(spacing: 7) {
                    Image(systemName: tab.kind.symbol)
                        .foregroundStyle(active ? LumaTheme.accent : LumaTheme.muted)
                    Text(tab.title).lineLimit(1).truncationMode(.middle)
                    if tab.isDirty {
                        Circle().fill(LumaTheme.warning).frame(width: 5, height: 5)
                            .accessibilityLabel("未保存")
                    }
                }.frame(maxWidth: 108, alignment: .leading)
            }
            .buttonStyle(LumaButtonStyle())
            .accessibilityAddTraits(active ? .isSelected : [])
            Button { workspace.close(tab.id) } label: {
                Image(systemName: "xmark").imageScale(.small)
            }
            .buttonStyle(LumaButtonStyle()).help("关闭 \(tab.title)").accessibilityLabel("关闭 \(tab.title)")
        }
        .background(active ? LumaTheme.selected : .clear, in: RoundedRectangle(cornerRadius: LumaTheme.controlRadius))
        .contentShape(Rectangle())
        .overlay(alignment: .bottom) {
            if active {
                Capsule().fill(LumaTheme.accent).frame(width: 19, height: 2)
                    .allowsHitTesting(false)
            }
        }
        .help(tab.url.path)
        .background(DocumentTabContextMenu(tab: tab, workspace: workspace))
    }
}

private struct FileItemContextMenu: View {
    let entry: FileEntry
    let workspace: Workspace
    var isWorkspaceRoot = false

    var body: some View {
        if entry.isDirectory {
            Button {
                workspace.newItemRequest = NewItemRequest(folder: entry.url)
            } label: { Label("新增文件…", systemImage: "doc.badge.plus") }
            .disabled(workspace.isMutatingFiles)
            Button {
                workspace.newItemRequest = NewItemRequest(folder: entry.url, kind: .folder)
            } label: { Label("新增文件夹…", systemImage: "folder.badge.plus") }
            .disabled(workspace.isMutatingFiles)
            Divider()
        }
        Button { workspace.renameRequest = entry } label: { Label("重命名…", systemImage: "pencil") }
            .disabled(workspace.isMutatingFiles)
        Button("在 Finder 中显示") { NSWorkspace.shared.activateFileViewerSelecting([entry.url]) }
        if entry.isDirectory { Button("刷新") { workspace.loadDirectory(entry.url, refresh: true) } }
        if isWorkspaceRoot { Button("从工作区移除") { workspace.removeFolder(entry.url) } }
        Divider()
        Button(role: .destructive) { workspace.trashRequest = entry }
            label: { Label("移到废纸篓…", systemImage: "trash") }
            .disabled(workspace.isMutatingFiles)
    }
}

private struct FileTreeRow: View {
    let entry: FileEntry
    let depth: Int
    @Bindable var workspace: Workspace

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            SidebarNativeRow(entry: entry, depth: depth, workspace: workspace, isWorkspaceRoot: depth == 0,
                             isExpanded: workspace.expanded.contains(entry.url), isSelected: workspace.activeID == entry.url)
                .frame(maxWidth: .infinity).frame(height: 30)
            if entry.isDirectory && workspace.expanded.contains(entry.url) {
                if let error = workspace.directoryErrors[entry.url] {
                    Text(error).font(.caption).foregroundStyle(.secondary).padding(.leading, 24)
                } else if let children = workspace.directories[entry.url] {
                    ForEach(children) { child in
                        FileTreeRow(entry: child, depth: depth + 1, workspace: workspace)
                    }
                    if children.isEmpty { Text("空文件夹").font(.caption).foregroundStyle(.tertiary).padding(.leading, CGFloat(depth + 1) * 12 + 24).padding(.vertical, 5) }
                } else { ProgressView().controlSize(.mini).padding(.leading, 30).padding(.vertical, 5) }
            }
        }
    }
}
