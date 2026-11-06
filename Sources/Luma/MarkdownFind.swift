import SwiftUI
import Observation

@Observable final class MarkdownFindState {
    private(set) var query = ""
    private(set) var request = 0
    private(set) var direction = 0
    var count = 0
    var current = 0
    var truncated = false
    var busy = false
    var error: String?

    var canMove: Bool { count > 0 && !busy && !query.isEmpty && error == nil }
    var status: String {
        if error != nil { return "搜索不可用" }
        if busy { return "查找中…" }
        if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "" }
        if count == 0 { return "无匹配" }
        return "\(current) / \(count.formatted())\(truncated ? "+" : "")"
    }

    func setQuery(_ value: String) {
        guard query != value else { return }
        query = value; direction = 0; request += 1
        count = 0; current = 0; truncated = false; error = nil
        busy = !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func move(_ direction: Int) {
        guard canMove else { return }
        self.direction = direction < 0 ? -1 : 1
        request += 1; busy = true
    }

    func clear() {
        setQuery("")
        count = 0; current = 0; truncated = false; busy = false; error = nil
    }

    func apply(_ values: [String: Any]) {
        count = max(0, values["count"] as? Int ?? 0)
        current = min(count, max(0, values["current"] as? Int ?? 0))
        truncated = values["truncated"] as? Bool ?? false
        error = values["error"] as? String
        busy = false
    }
}

struct MarkdownFindBar: View {
    @Bindable var search: MarkdownFindState
    let focusRequest: Int
    let onClose: () -> Void
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("在 Markdown 正文中查找", text: Binding(get: { search.query }, set: search.setQuery))
                .textFieldStyle(.plain).focused($focused)
                .accessibilityLabel("Markdown 正文搜索")
                .onSubmit { search.move(1) }
                .onKeyPress(keys: [.return], phases: .down) { press in
                    guard press.modifiers.contains(.shift) else { return .ignored }
                    search.move(-1)
                    return .handled
                }
            Text(search.status).font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
                .lineLimit(1).fixedSize().help(search.error ?? (search.truncated ? "显示前 5,000 处匹配" : "匹配结果"))
                .accessibilityLabel(search.status)
            Button { search.move(-1) } label: { Image(systemName: "chevron.up").frame(width: 20, height: 24) }
                .disabled(!search.canMove).help("上一个匹配 ⇧↩ / ⇧⌘G").accessibilityLabel("上一个匹配")
            Button { search.move(1) } label: { Image(systemName: "chevron.down").frame(width: 20, height: 24) }
                .disabled(!search.canMove).help("下一个匹配 ↩ / ⌘G").accessibilityLabel("下一个匹配")
            Button(action: onClose) { Image(systemName: "xmark").frame(width: 20, height: 24) }
                .help("关闭查找 Esc").accessibilityLabel("关闭查找")
        }
        .font(.system(size: 12)).buttonStyle(.plain).padding(.horizontal, 22).frame(height: 38)
        .background(.quaternary.opacity(0.25))
        .onAppear { focused = true }
        .onChange(of: focusRequest) { _, _ in focused = true }
        .onExitCommand(perform: onClose)
    }
}
