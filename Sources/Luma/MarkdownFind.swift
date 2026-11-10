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
        if error != nil { return tr("搜索不可用") }
        if busy { return tr("查找中…") }
        if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "" }
        if count == 0 { return tr("无匹配") }
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
    @ViewState private var focused = false

    var body: some View {
        HStack(spacing: 5) {
            HStack(spacing: 7) {
                Image(systemName: "magnifyingglass").foregroundStyle(LumaTheme.muted).accessibilityHidden(true)
                // Swift 6.2 crashes when adapting the isolated setter method reference.
                SearchTextField(text: Binding(get: { search.query }, set: { search.setQuery($0) }),
                                placeholder: tr("在 Markdown 正文中查找"), accessibilityLabel: tr("Markdown 正文搜索"),
                                focusRequest: focusRequest, onFocusChange: { focused = $0 },
                                onSubmit: { search.move($0 ? -1 : 1) }, onCancel: onClose)
            }.lumaField(focused: focused)
            Text(search.status).font(.system(size: 11).monospacedDigit()).foregroundStyle(LumaTheme.muted)
                .lineLimit(1).fixedSize().help(search.error ?? (search.truncated ? tr("显示前 5,000 处匹配") : tr("匹配结果")))
                .accessibilityLabel(search.status)
            Button { search.move(-1) } label: { Image(systemName: "chevron.up") }
                .disabled(!search.canMove).help(tr("上一个匹配 ⇧↩ / ⇧⌘G")).accessibilityLabel(tr("上一个匹配"))
            Button { search.move(1) } label: { Image(systemName: "chevron.down") }
                .disabled(!search.canMove).help(tr("下一个匹配 ↩ / ⌘G")).accessibilityLabel(tr("下一个匹配"))
            Button(action: onClose) { Image(systemName: "xmark") }
                .help(tr("关闭查找 Esc")).accessibilityLabel(tr("关闭查找"))
        }
        .font(.system(size: 12)).buttonStyle(LumaButtonStyle())
        .padding(.horizontal, 16).padding(.vertical, 6).background(LumaTheme.chrome)
        .onExitCommand(perform: onClose)
    }
}
