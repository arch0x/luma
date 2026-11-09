import SwiftUI
import ReaderCore

nonisolated enum WorkspaceRenameError: LocalizedError {
    case busy, targetOpen
    var errorDescription: String? {
        switch self {
        case .busy: "相关文档正在读写或执行文件操作，请稍后重试。"
        case .targetOpen: "目标路径已在其他标签中打开，请先关闭该标签或更换位置。"
        }
    }
}

struct RenameSheet: View {
    let entry: FileEntry
    let workspace: Workspace
    @Environment(\.dismiss) private var dismiss
    @ViewState private var name: String
    @ViewState private var failure: String?
    @ViewState private var working = false
    @FocusState private var nameFocused: Bool

    init(entry: FileEntry, workspace: Workspace) {
        self.entry = entry
        self.workspace = workspace
        _name = ViewState(initialValue: entry.name)
    }
    private var validName: String? { try? FileCreator.validatedName(name) }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label(entry.isDirectory ? "重命名文件夹" : "重命名文件", systemImage: "pencil")
                .font(.title3.weight(.semibold)).foregroundStyle(LumaTheme.accent)
            Text(entry.url.path).font(.caption).foregroundStyle(.secondary)
                .lineLimit(2).truncationMode(.middle).help(entry.url.path)
            VStack(alignment: .leading, spacing: 8) {
                Text("新名称").font(.callout.weight(.medium))
                TextField("请输入新名称", text: $name)
                    .textFieldStyle(.plain).disableAutocorrection(true)
                    .focused($nameFocused).disabled(working)
                    .accessibilityLabel("重命名后的名称")
                    .onSubmit(rename)
                    .onChange(of: name) { _, _ in failure = nil }
                    .lumaField(focused: nameFocused)
                if let message = failure ?? (validName == nil ? FileCreationError.invalidName.localizedDescription : nil) {
                    Text(message).font(.caption).foregroundStyle(LumaTheme.danger)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("已打开的文件标签和保存路径会同步更新。")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            LumaRule()
            HStack(spacing: 8) {
                if working { ProgressView().controlSize(.small) }
                Spacer()
                Button("取消") { dismiss() }
                    .buttonStyle(LumaButtonStyle(emphasis: .secondary)).keyboardShortcut(.cancelAction).disabled(working)
                Button("重命名", action: rename).buttonStyle(LumaButtonStyle(emphasis: .primary))
                    .keyboardShortcut(.defaultAction)
                    .disabled(working || validName == nil || validName == entry.name)
            }
        }
        .padding(24).frame(width: 440)
        .background(LumaTheme.paper)
        .tint(LumaTheme.accent).accentColor(LumaTheme.accent)
        .interactiveDismissDisabled(working)
        .onAppear { nameFocused = true }
    }

    private func rename() {
        guard !working, let name = validName, name != entry.name else { return }
        working = true
        failure = nil
        Task {
            do { _ = try await workspace.rename(entry, to: name); dismiss() }
            catch { failure = "重命名失败：\(error.localizedDescription)" }
            working = false
        }
    }
}
