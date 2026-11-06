import SwiftUI
import AppKit
import ReaderCore

struct WorkspaceView: View {
    @Bindable var workspace: Workspace
    @ViewState private var visibility = NavigationSplitViewVisibility.all
    @ViewState private var dropTarget = false

    var body: some View {
        NavigationSplitView(columnVisibility: $visibility) {
            sidebar.navigationSplitViewColumnWidth(min: 205, ideal: 245, max: 380)
        } detail: {
            VStack(spacing: 0) {
                if !workspace.tabs.isEmpty { tabBar; Divider() }
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
                            .buttonStyle(.plain).accessibilityLabel("关闭提示")
                    }
                    .padding(12).background(.quaternary)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .textBackgroundColor))
            .overlay {
                if dropTarget {
                    RoundedRectangle(cornerRadius: 12).strokeBorder(LumaTheme.accent, style: StrokeStyle(lineWidth: 2, dash: [8]))
                        .padding(10).allowsHitTesting(false)
                }
            }
        }
        .tint(LumaTheme.accent)
        .accentColor(LumaTheme.accent)
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
                Button(action: workspace.chooseFolder) { Image(systemName: "folder.badge.plus") }
                    .help("添加文件夹 ⇧⌘O")
                Button(action: workspace.chooseFiles) { Image(systemName: "doc.badge.plus") }
                    .help("打开文件 ⌘O")
            }
            ToolbarItemGroup(placement: .primaryAction) {
                if let tab = workspace.activeTab {
                    Button { NSWorkspace.shared.activateFileViewerSelecting([tab.url]) } label: {
                        Image(systemName: "folder")
                    }.help("在 Finder 中显示")
                }
                Button(action: workspace.refresh) { Image(systemName: "arrow.clockwise") }
                    .help("刷新目录与当前文件 ⌘R")
                    .accessibilityLabel("刷新目录与当前文件")
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            let files = urls.filter(\.isFileURL)
            guard !files.isEmpty else { return false }
            workspace.open(files)
            return true
        } isTargeted: { dropTarget = $0 }
        .onChange(of: workspace.query) { _, _ in workspace.search() }
        .onChange(of: workspace.roots) { _, _ in if !workspace.query.isEmpty { workspace.search() } }
        .onChange(of: workspace.activeID) { _, _ in Task { await workspace.checkExternalChanges() } }
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                BrandMark(size: 28)
                Text("Luma").font(.system(size: 19, weight: .semibold, design: .rounded))
                Spacer()
                Text("澄览").font(.caption).foregroundStyle(.secondary)
            }.padding(.horizontal, 18).padding(.top, 20).padding(.bottom, 22)

            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("搜索文件名", text: $workspace.query).textFieldStyle(.plain)
                    .accessibilityLabel("搜索工作区文件名")
                if !workspace.query.isEmpty {
                    Button { workspace.query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary) }
                        .buttonStyle(.plain).accessibilityLabel("清除搜索")
                }
            }
            .padding(8).background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 7))
            .padding(.horizontal, 12).padding(.bottom, 16)

            HStack {
                Text(workspace.query.isEmpty ? "工作区" : "搜索结果")
                    .font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                Spacer()
                if workspace.searching { ProgressView().controlSize(.mini) }
                else { Text(workspace.query.isEmpty ? "\(workspace.roots.count)" : "\(workspace.searchResults.count)").font(.caption2).foregroundStyle(.tertiary) }
            }.padding(.horizontal, 18).padding(.bottom, 8)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    if !workspace.query.isEmpty {
                        searchResults
                    } else if workspace.roots.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("把常用文件夹放在这里，\n文件就能触手可及。")
                                .font(.callout).foregroundStyle(.secondary).lineSpacing(5)
                            Button("添加文件夹…", action: workspace.chooseFolder).controlSize(.small)
                        }.padding(18)
                    } else {
                        ForEach(workspace.roots, id: \.self) { root in
                            FileTreeRow(entry: FileEntry(url: root, isDirectory: true), depth: 0, workspace: workspace)
                        }
                    }
                }.padding(.horizontal, 8)
            }
            Spacer(minLength: 0)
            Divider().padding(.horizontal, 14)
            HStack {
                Image(systemName: "internaldrive").font(.caption)
                Text("本地文件 · 手动保存").font(.system(size: 10))
                Spacer()
                SettingsLink { Image(systemName: "gearshape") }.buttonStyle(.plain).help("设置 ⌘,")
            }.foregroundStyle(.secondary).padding(16)
        }
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.45))
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
            }.buttonStyle(.plain).help(entry.url.path)
                .contextMenu { FileItemContextMenu(entry: entry, workspace: workspace) }
        }
        if workspace.searchResults.count == 200 {
            Text("最多显示 200 项，请缩小关键词。")
                .font(.caption).foregroundStyle(.secondary).padding(8)
        }
    }

    private var tabBar: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    ForEach(workspace.tabs) { tab in
                        HStack(spacing: 7) {
                            Button { workspace.activeID = tab.id } label: {
                                HStack(spacing: 7) {
                                    Image(systemName: tab.kind.symbol).foregroundStyle(tab.id == workspace.activeID ? LumaTheme.accent : .secondary)
                                    Text(tab.title).lineLimit(1).truncationMode(.middle)
                                    if tab.isDirty { Circle().fill(LumaTheme.accent).frame(width: 6, height: 6).accessibilityLabel("未保存") }
                                }.contentShape(Rectangle())
                            }.buttonStyle(.plain)
                            Button { workspace.close(tab.id) } label: {
                                Image(systemName: "xmark").font(.system(size: 9, weight: .medium))
                                    .foregroundStyle(.secondary).frame(width: 18, height: 20).contentShape(Rectangle())
                            }.buttonStyle(.plain).help("关闭 \(tab.title)").accessibilityLabel("关闭 \(tab.title)")
                        }
                        .font(.system(size: 12))
                        .padding(.leading, 14).padding(.trailing, 7).frame(height: 40)
                        .background(tab.id == workspace.activeID ? Color(nsColor: .textBackgroundColor) : Color.clear)
                        .overlay(alignment: .bottom) { if tab.id == workspace.activeID { LumaTheme.accent.frame(height: 2) } }
                        .overlay(alignment: .trailing) { Divider().padding(.vertical, 10) }
                        .id(tab.id).help(tab.url.path)
                        .contextMenu {
                            Button("在 Finder 中显示") { NSWorkspace.shared.activateFileViewerSelecting([tab.url]) }
                            Button("关闭标签页") { workspace.close(tab.id) }
                        }
                    }
                }
            }
            .onChange(of: workspace.activeID) { _, value in if let value { proxy.scrollTo(value) } }
        }
        .background(Color(nsColor: .windowBackgroundColor))
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

struct BrandMark: View {
    var size: CGFloat
    private static let logo: NSImage = {
        guard let url = Bundle.module.url(forResource: "AppIcon", withExtension: "png", subdirectory: "Brand"),
              let image = NSImage(contentsOf: url) else {
            preconditionFailure("Missing bundled Luma logo: Brand/AppIcon.png")
        }
        return image
    }()

    var body: some View {
        Image(nsImage: Self.logo)
            .renderingMode(.original)
            .resizable()
            .interpolation(.high)
            .scaledToFit()
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}
