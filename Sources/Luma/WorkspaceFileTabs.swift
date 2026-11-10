import SwiftUI

/// Shared by the workspace and native toolbar integration tests.
struct WorkspaceFileTabs: View {
    @Bindable var workspace: Workspace
    let width: CGFloat

    var body: some View {
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
            .onChange(of: width) { _, _ in
                if let id = workspace.activeID { scroll.scrollTo(id) }
            }
        }
        .frame(minWidth: 0, idealWidth: width, maxWidth: width, alignment: .leading)
        .frame(height: 31)
        .background(WorkspaceTabViewport())
        .accessibilityElement(children: .contain)
        .accessibilityLabel(tr("已打开的文件"))
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
                            .accessibilityLabel(tr("未保存"))
                    }
                }.frame(maxWidth: 108, alignment: .leading)
            }
            .buttonStyle(LumaButtonStyle())
            .accessibilityAddTraits(active ? .isSelected : [])
            Button { workspace.close(tab.id) } label: {
                Image(systemName: "xmark").imageScale(.small)
            }
            .buttonStyle(LumaButtonStyle()).help(tr("关闭 \(tab.title)")).accessibilityLabel(tr("关闭 \(tab.title)"))
        }
        .background(active ? LumaTheme.selected : .clear, in: RoundedRectangle(cornerRadius: LumaTheme.controlRadius))
        .contentShape(Rectangle())
        .help(tab.url.path)
        .background(DocumentTabContextMenu(tab: tab, workspace: workspace))
    }
}
