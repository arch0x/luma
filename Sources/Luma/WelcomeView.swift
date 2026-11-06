import SwiftUI

struct WelcomeView: View {
    @Bindable var workspace: Workspace

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 8) {
                    Circle().fill(LumaTheme.accent).frame(width: 5, height: 5)
                    Text("你的本地阅读空间").font(.system(size: 11, weight: .medium)).tracking(2).foregroundStyle(.secondary)
                }.padding(.bottom, 24)

                Text("万千文件，\n一处澄览。")
                    .font(.system(size: 46, weight: .medium, design: .serif))
                    .tracking(-1).lineSpacing(8).padding(.bottom, 18)
                Text("文档、数据与代码，在同一个窗口里安静展开。")
                    .font(.system(size: 14)).foregroundStyle(.secondary).padding(.bottom, 36)

                HStack(spacing: 12) {
                    Button(action: workspace.chooseFiles) {
                        HStack { Image(systemName: "plus"); Text("打开文件"); Text("⌘O").opacity(0.6) }.padding(.horizontal, 10).padding(.vertical, 5)
                    }.buttonStyle(.borderedProminent).controlSize(.large)
                    Button(action: workspace.chooseFolder) {
                        HStack { Image(systemName: "folder"); Text("添加文件夹") }.padding(.horizontal, 6).padding(.vertical, 5)
                    }.controlSize(.large)
                }.padding(.bottom, 18)
                Text("也可以把文件或文件夹拖到窗口中")
                    .font(.system(size: 11)).foregroundStyle(.tertiary).padding(.bottom, 40)

                HStack(spacing: 0) {
                    format("text.document", "文档", "Markdown · PDF")
                    Divider().frame(height: 36).padding(.horizontal, 24)
                    format("tablecells", "数据", "JSON · CSV · TSV")
                    Divider().frame(height: 36).padding(.horizontal, 24)
                    format("photo", "更多", "图片 · 文本 · 代码")
                }.padding(.bottom, 36)

                Divider().padding(.bottom, 22)
                HStack {
                    Text("从这里开始").font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                    Spacer()
                    Text("01 / 本地优先").font(.system(size: 10, design: .monospaced)).foregroundStyle(.tertiary)
                }.padding(.bottom, 14)
                Button(action: workspace.openSamples) {
                    HStack(spacing: 12) {
                        Image(systemName: "sparkles").font(.system(size: 18)).foregroundStyle(LumaTheme.accent)
                            .frame(width: 40, height: 40).background(LumaTheme.accent.opacity(0.07), in: RoundedRectangle(cornerRadius: 9))
                        VStack(alignment: .leading, spacing: 4) {
                            Text("逛逛示例工作区").font(.system(size: 13, weight: .medium))
                            Text("一份文档、一组数据，感受不同文件的阅读方式").font(.system(size: 11)).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "arrow.up.right").font(.system(size: 12)).foregroundStyle(.secondary)
                    }.padding(12).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))

                if !workspace.recent.isEmpty {
                    Text("最近的文件夹").font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                        .padding(.top, 24).padding(.bottom, 8)
                    ForEach(workspace.recent.prefix(3), id: \.self) { url in
                        Button { workspace.addFolder(url) } label: {
                            HStack {
                                Image(systemName: "folder").foregroundStyle(.secondary)
                                Text(url.lastPathComponent).font(.system(size: 12))
                                Spacer()
                                Text(url.deletingLastPathComponent().path).font(.system(size: 10)).foregroundStyle(.tertiary).lineLimit(1).truncationMode(.middle)
                            }.padding(.vertical, 6).contentShape(Rectangle())
                        }.buttonStyle(.plain).help(url.path)
                    }
                }
            }
            .frame(maxWidth: 580, alignment: .leading)
            .padding(.horizontal, 50).padding(.vertical, 58)
            .frame(maxWidth: .infinity, minHeight: 650)
        }
    }

    private func format(_ symbol: String, _ title: String, _ subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Label(title, systemImage: symbol).font(.system(size: 12, weight: .medium))
            Text(subtitle).font(.system(size: 10)).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}
