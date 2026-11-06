import SwiftUI

struct MarkdownHeading: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let level: Int
}

struct MarkdownOutlineItem: Identifiable, Equatable, Sendable {
    let heading: MarkdownHeading
    let parents: [String]
    let hasChildren: Bool
    var id: String { heading.id }
    var depth: Int { parents.count }

    static func make(_ headings: [MarkdownHeading]) -> [Self] {
        var ancestors: [MarkdownHeading] = []
        return headings.enumerated().map { index, heading in
            while let last = ancestors.last, last.level >= heading.level { ancestors.removeLast() }
            let item = Self(heading: heading, parents: ancestors.map(\.id), hasChildren: index + 1 < headings.count && headings[index + 1].level > heading.level)
            ancestors.append(heading)
            return item
        }
    }
}

struct MarkdownOutlineView: View {
    @Bindable var state: MarkdownRenderState
    @Bindable var tab: DocumentTab
    var onNavigate: () -> Void = {}

    private var items: [MarkdownOutlineItem] { MarkdownOutlineItem.make(state.headings) }
    private var visibleItems: [MarkdownOutlineItem] {
        items.filter { $0.parents.allSatisfy { !tab.markdownCollapsedHeadings.contains($0) } }
    }
    private var visibleActiveID: String? {
        guard let current = items.first(where: { $0.id == state.activeHeadingID }) else { return nil }
        return current.parents.first(where: tab.markdownCollapsedHeadings.contains) ?? current.id
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("文档大纲").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                Spacer()
                Menu {
                    Button("全部展开") { tab.markdownCollapsedHeadings.removeAll() }
                    Button("折叠所有章节") { tab.markdownCollapsedHeadings = Set(items.filter(\.hasChildren).map(\.id)) }
                } label: { Image(systemName: "ellipsis").frame(width: 22, height: 22) }
                .menuStyle(.borderlessButton).fixedSize().help("大纲显示选项")
                .accessibilityLabel("大纲显示选项")
            }.padding(.horizontal, 14).padding(.top, 12).padding(.bottom, 8)

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(visibleItems) { item in
                            HStack(alignment: .top, spacing: 3) {
                                if item.hasChildren {
                                    Button {
                                        if tab.markdownCollapsedHeadings.contains(item.id) { tab.markdownCollapsedHeadings.remove(item.id) }
                                        else { tab.markdownCollapsedHeadings.insert(item.id) }
                                    } label: {
                                        Image(systemName: tab.markdownCollapsedHeadings.contains(item.id) ? "chevron.right" : "chevron.down")
                                            .font(.system(size: 8, weight: .semibold)).frame(width: 16, height: 25)
                                    }
                                    .buttonStyle(.plain).foregroundStyle(.secondary)
                                    .accessibilityLabel("\(tab.markdownCollapsedHeadings.contains(item.id) ? "展开" : "折叠") \(item.heading.title)")
                                } else { Color.clear.frame(width: 16, height: 25) }
                                Button {
                                    state.navigate(to: item.id)
                                    onNavigate()
                                } label: {
                                    Text(item.heading.title)
                                        .font(.system(size: 11, weight: item.id == visibleActiveID ? .semibold : .regular))
                                        .foregroundStyle(item.id == visibleActiveID ? LumaTheme.accent : .secondary)
                                        .lineLimit(2).multilineTextAlignment(.leading)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(.vertical, 6).contentShape(Rectangle())
                                }.buttonStyle(.plain).help(item.heading.title)
                                    .accessibilityValue(item.id == visibleActiveID ? "当前章节" : "H\(item.heading.level)")
                            }
                            .padding(.leading, CGFloat(item.depth) * 10 + 3).padding(.trailing, 8)
                            .background(item.id == visibleActiveID ? LumaTheme.accent.opacity(0.09) : .clear, in: RoundedRectangle(cornerRadius: 5))
                            .id(item.id)
                        }
                    }.padding(.horizontal, 8).padding(.bottom, 16)
                }
                .onChange(of: visibleActiveID, initial: true) { _, id in if let id { proxy.scrollTo(id, anchor: .center) } }
            }
            if state.outlineTruncated {
                Text("显示前 2,000 个标题").font(.system(size: 10)).foregroundStyle(.tertiary).padding(12)
            }
        }
        .tint(LumaTheme.accent)
        .accentColor(LumaTheme.accent)
        .disabled(state.loading)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
        .accessibilityElement(children: .contain).accessibilityLabel("文档大纲")
    }
}
