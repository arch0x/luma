import SwiftUI

struct WelcomeView: View {
    @Bindable var workspace: Workspace

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 30) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(tr("开始阅读"))
                        .font(.system(size: 34, weight: .semibold, design: .serif))
                        .accessibilityAddTraits(.isHeader)
                    Text(tr("打开文件，或把文件夹拖进资料库。"))
                        .font(.callout).foregroundStyle(LumaTheme.muted)
                }

                if workspace.recent.isEmpty {
                    openingActions.frame(maxWidth: 420, alignment: .leading)
                } else {
                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .top, spacing: 28) {
                            openingActions.frame(minWidth: 260, maxWidth: 400)
                            recentFolders.frame(minWidth: 250, maxWidth: 360)
                        }
                        VStack(alignment: .leading, spacing: 24) {
                            openingActions
                            recentFolders
                        }
                    }
                }
            }
            .frame(maxWidth: 760, alignment: .leading)
            .padding(.horizontal, 30).padding(.vertical, 44)
            .frame(maxWidth: .infinity)
        }
        .background(LumaTheme.paper)
    }

    private var openingActions: some View {
        VStack(alignment: .leading, spacing: 0) {
            actionRow(tr("打开文件"), symbol: "doc.badge.plus", detail: "⌘O", action: workspace.chooseFiles)
            LumaRule()
            actionRow(tr("打开文件夹"), symbol: "folder.badge.plus", detail: "⇧⌘O", action: workspace.chooseFolder)
            LumaRule()
            actionRow(tr("打开示例工作区"), symbol: "books.vertical", action: workspace.openSamples)
        }
    }

    private var recentFolders: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(tr("最近使用的文件夹"))
                .font(.caption.weight(.semibold)).foregroundStyle(LumaTheme.muted)
                .accessibilityAddTraits(.isHeader)
                .padding(.horizontal, 7)
            ForEach(workspace.recent.prefix(4), id: \.self) { url in
                Button { workspace.addFolder(url) } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "folder").foregroundStyle(LumaTheme.accent)
                            .frame(width: 23)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(url.lastPathComponent).lineLimit(1).truncationMode(.middle)
                            Text(url.deletingLastPathComponent().path)
                                .font(.caption).foregroundStyle(LumaTheme.muted)
                                .lineLimit(1).truncationMode(.middle)
                        }
                        Spacer(minLength: 0)
                    }.padding(.vertical, 5)
                }.buttonStyle(LumaButtonStyle()).help(url.path)
            }
        }
    }

    private func actionRow(_ title: String, symbol: String, detail: String? = nil,
                           action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: symbol).foregroundStyle(LumaTheme.accent).frame(width: 23)
                Text(title)
                Spacer(minLength: 8)
                if let detail { Text(detail).font(.caption).foregroundStyle(LumaTheme.muted) }
                else { Image(systemName: "chevron.right").imageScale(.small).foregroundStyle(LumaTheme.muted) }
            }.frame(minHeight: 42)
        }.buttonStyle(LumaButtonStyle())
    }
}
