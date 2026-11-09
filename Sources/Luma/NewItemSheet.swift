import SwiftUI
import ReaderCore

enum NewItemKind {
    case file, folder
    var title: String { self == .file ? "新增文件" : "新增文件夹" }
    var label: String { self == .file ? "文件名" : "文件夹名称" }
    var symbol: String { self == .file ? "doc.badge.plus" : "folder.badge.plus" }
}

struct NewItemRequest: Identifiable {
    let folder: URL
    var kind: NewItemKind = .file
    var id: URL { folder }
}

struct NewItemSheet: View {
    let folder: URL
    var kind: NewItemKind = .file
    let workspace: Workspace
    @Environment(\.dismiss) private var dismiss
    @ViewState private var filename = ""
    @ViewState private var failure: String?
    @ViewState private var creating = false
    @FocusState private var filenameFocused: Bool

    private var validName: String? { try? FileCreator.validatedName(filename) }
    private var validationMessage: String? {
        guard !filename.isEmpty, validName == nil else { return nil }
        return FileCreationError.invalidName.localizedDescription
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label(kind.title, systemImage: kind.symbol)
                .font(.title3.weight(.semibold)).foregroundStyle(LumaTheme.accent)
            Text("创建位置：\(folder.path)")
                .font(.caption).foregroundStyle(.secondary)
                .lineLimit(2).truncationMode(.middle).help(folder.path)
            VStack(alignment: .leading, spacing: 8) {
                Text(kind.label).font(.callout.weight(.medium))
                TextField(kind == .file ? "例如：笔记.md 或 说明.txt" : "例如：文档 或 项目资料", text: $filename)
                    .textFieldStyle(.plain)
                    .disableAutocorrection(true)
                    .focused($filenameFocused)
                    .disabled(creating)
                    .accessibilityLabel(kind.label)
                    .onSubmit(create)
                    .onChange(of: filename) { _, _ in failure = nil }
                    .lumaField(focused: filenameFocused)
                if let message = failure ?? validationMessage {
                    Text(message).font(.caption).foregroundStyle(LumaTheme.danger)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text(kind == .file ? "创建空文件；使用 .md、.txt 等扩展名可指定文件类型。" : "将在当前文件夹内创建一个空文件夹。")
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            LumaRule()
            HStack(spacing: 8) {
                if creating { ProgressView().controlSize(.small) }
                Spacer()
                Button("取消") { dismiss() }
                    .buttonStyle(LumaButtonStyle(emphasis: .secondary))
                    .keyboardShortcut(.cancelAction).disabled(creating)
                Button("创建", action: create)
                    .buttonStyle(LumaButtonStyle(emphasis: .primary))
                    .keyboardShortcut(.defaultAction)
                    .disabled(creating || validName == nil)
            }
        }
        .padding(24).frame(width: 440)
        .background(LumaTheme.paper)
        .tint(LumaTheme.accent).accentColor(LumaTheme.accent)
        .interactiveDismissDisabled(creating)
        .onAppear { filenameFocused = true }
    }

    private func create() {
        guard !creating, let name = validName else { return }
        creating = true
        failure = nil
        Task {
            do {
                if kind == .file { _ = try await workspace.createFile(named: name, in: folder) }
                else { _ = try await workspace.createFolder(named: name, in: folder) }
                dismiss()
            } catch {
                failure = "创建失败：\(error.localizedDescription)"
            }
            creating = false
        }
    }
}
