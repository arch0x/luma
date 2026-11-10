import SwiftUI
import Observation

@Observable final class MarkdownSectionPeek {
    private(set) var headingID: String?
    @ObservationIgnored private var dismissal: Task<Void, Never>?

    func show(_ id: String) {
        keepOpen()
        if headingID != id { headingID = id }
    }

    func keepOpen() {
        dismissal?.cancel()
        dismissal = nil
    }

    func dismissSoon() {
        keepOpen()
        guard headingID != nil else { return }
        dismissal = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(300)) }
            catch { return }
            self?.dismiss()
        }
    }

    func dismiss() {
        keepOpen()
        headingID = nil
    }
}

struct MarkdownSectionRail: View {
    let state: MarkdownRenderState
    let peek: MarkdownSectionPeek
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ViewState private var pointerY: CGFloat?
    @FocusState private var focusedID: String?

    private static let rowHeight: CGFloat = 18
    static func contentHeight(for state: MarkdownRenderState) -> CGFloat {
        state.headings.isEmpty ? 28 : CGFloat(state.headings.count) * rowHeight + 12
    }
    private let markWidth: CGFloat = 7
    private let expandedMarkWidth: CGFloat = 24
    private var hoveredID: String? {
        guard let pointerY, pointerY >= 0 else { return nil }
        let index = Int(pointerY / Self.rowHeight)
        return state.headings.indices.contains(index) ? state.headings[index].id : nil
    }
    private var previewID: String? { peek.headingID ?? focusedID }

    var body: some View {
        Group {
            if state.headings.isEmpty { bookmarkMark }
            else { chapterMarks }
        }
        .frame(width: 38)
        .background(LumaTheme.paper)
        .disabled(state.loading && state.headings.isEmpty)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(tr("章节导航"))
        .accessibilityHint(state.outlineTruncated ? tr("显示前 2,000 个标题") : "")
    }

    private var chapterMarks: some View {
        GeometryReader { geometry in
            ScrollViewReader { scroll in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(state.headings.indices, id: \.self) { index in
                            let heading = state.headings[index]
                            mark(for: heading, at: index).id(heading.id)
                        }
                    }
                    .contentShape(Rectangle())
                    .onContinuousHover { phase in
                        switch phase {
                        case .active(let point):
                            pointerY = point.y
                            if let hoveredID { peek.show(hoveredID) }
                        case .ended:
                            pointerY = nil
                            peek.dismissSoon()
                        }
                    }
                    .padding(.vertical, 6)
                }
                .frame(height: min(Self.contentHeight(for: state), max(0, geometry.size.height)))
                .scrollIndicators(.hidden)
                .onChange(of: state.activeHeadingID, initial: true) { _, id in
                    if previewID == nil, let id { scroll.scrollTo(id) }
                }
                .onChange(of: previewID) { _, id in
                    if id == nil, let current = state.activeHeadingID { scroll.scrollTo(current) }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var bookmarkMark: some View {
        Button { peek.show("") } label: {
            Image(systemName: "bookmark")
                .font(.system(size: 12)).foregroundStyle(LumaTheme.sectionMark)
                .frame(width: 32, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focused($focusedID, equals: "")
        .accessibilityLabel(tr("阅读书签"))
        .onHover { inside in
            if inside { peek.show("") }
            else { peek.dismissSoon() }
        }
        .anchorPreference(key: SectionMarkAnchor.self, value: .bounds) {
            previewID == "" ? SectionMarkPreview(heading: nil, bounds: $0) : nil
        }
        .frame(maxHeight: .infinity)
    }

    private func mark(for heading: MarkdownHeading, at index: Int) -> some View {
        let current = state.activeHeadingID == heading.id
        let hovered = hoveredID == heading.id
        let thickness: CGFloat = current ? 3 : 2
        let lift = hoverStrength(at: index, isHovered: hovered)
        return Button {
            pointerY = nil
            peek.dismiss()
            state.navigate(to: heading.id)
        } label: {
            Capsule()
                .fill(current ? LumaTheme.currentSectionMark : LumaTheme.sectionMark)
                .frame(width: markWidth, height: thickness)
                .scaleEffect(x: 1 + lift * (expandedMarkWidth / markWidth - 1),
                             y: 1 + lift * (4 / thickness - 1), anchor: .leading)
                .animation(reduceMotion ? nil : .timingCurve(0.23, 1, 0.32, 1, duration: pointerY == nil ? 0.18 : 0.125),
                           value: lift)
                .frame(width: 31, height: Self.rowHeight, alignment: .leading)
                .padding(.leading, 7)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focused($focusedID, equals: heading.id)
        .overlay {
            if focusedID == heading.id {
                RoundedRectangle(cornerRadius: 4).strokeBorder(LumaTheme.accent)
                    .padding(.horizontal, 2).allowsHitTesting(false)
            }
        }
        .anchorPreference(key: SectionMarkAnchor.self, value: .bounds) {
            previewID == heading.id ? SectionMarkPreview(heading: heading, bounds: $0) : nil
        }
        .accessibilityLabel(heading.title)
        .accessibilityValue(current ? tr("当前章节") : tr("第 \(heading.level) 级标题"))
        .accessibilityHint(heading.summary)
        .accessibilityAddTraits(current ? .isSelected : [])
        .accessibilityAction(named: Text(tr("打开章节和书签卡片"))) { peek.show(heading.id) }
    }

    private func hoverStrength(at index: Int, isHovered: Bool) -> CGFloat {
        guard let pointerY else { return 0 }
        if reduceMotion { return isHovered ? 1 : 0 }
        let center = (CGFloat(index) + 0.5) * Self.rowHeight
        let proximity = max(0, 1 - abs(pointerY - center) / (3 * Self.rowHeight))
        return proximity * proximity
    }
}

extension View {
    func markdownSectionPreview(tab: DocumentTab, state: MarkdownRenderState, peek: MarkdownSectionPeek, suppressed: Bool = false) -> some View {
        overlayPreferenceValue(SectionMarkAnchor.self) { preview in
            GeometryReader { geometry in
                if let preview, !suppressed {
                    let mark = geometry[preview.bounds]
                    let summaryHeight: CGFloat = preview.heading.map { $0.summary.isEmpty ? 55 : 112 } ?? 0
                    let bookmarksHeight = tab.readingSession.map { 38 + CGFloat(min(3, $0.bookmarks.count)) * 32 } ?? 0
                    let height = summaryHeight + bookmarksHeight
                    let width = min(266, geometry.size.width - mark.maxX - 16)
                    if width > 100 && mark.midY >= 0 && mark.midY <= geometry.size.height {
                        let top = max(6, min(mark.midY - 24, geometry.size.height - height - 6))
                        SectionSummaryCard(heading: preview.heading, summaryHeight: summaryHeight,
                                           tab: tab, state: state, peek: peek)
                            .frame(width: width)
                            .onHover { inside in
                                if inside {
                                    peek.show(preview.heading?.id ?? "")
                                } else {
                                    peek.dismissSoon()
                                }
                            }
                            .onExitCommand { peek.dismiss() }
                            .position(x: mark.maxX + width / 2 + 8,
                                      y: top + height / 2)
                    }
                }
            }
        }
    }
}

private struct SectionSummaryCard: View {
    let heading: MarkdownHeading?
    let summaryHeight: CGFloat
    let tab: DocumentTab
    let state: MarkdownRenderState
    let peek: MarkdownSectionPeek

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let heading {
                VStack(alignment: .leading, spacing: 6) {
                    Text(heading.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(LumaTheme.ink)
                        .lineLimit(2)
                    if !heading.summary.isEmpty {
                        Text(heading.summary)
                            .font(.system(size: 12))
                            .foregroundStyle(LumaTheme.muted)
                            .lineLimit(4)
                    }
                }
                .padding(11)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .frame(height: summaryHeight, alignment: .topLeading)
                .overlay(alignment: .bottom) { LumaRule().allowsHitTesting(false) }
            }
            if let session = tab.readingSession {
                MarkdownBookmarksView(session: session,
                                      addTitle: heading == nil ? tr("添加当前位置") : tr("添加本节书签"),
                                      adding: state.addingBookmark || state.loading,
                                      onAdd: { tab.requestReadingBookmark(headingID: heading?.id) },
                                      onSelect: { location in
                                          peek.dismiss()
                                          state.navigate(to: location)
                                      })
            }
        }
        .background(LumaTheme.control, in: RoundedRectangle(cornerRadius: LumaTheme.groupRadius))
        .overlay {
            RoundedRectangle(cornerRadius: LumaTheme.groupRadius).strokeBorder(LumaTheme.controlBorder)
                .allowsHitTesting(false)
        }
        .contentShape(Rectangle())
        .shadow(color: .black.opacity(0.14), radius: 8, y: 3)
    }
}

private struct SectionMarkPreview {
    let heading: MarkdownHeading?
    let bounds: Anchor<CGRect>
}

nonisolated private enum SectionMarkAnchor: PreferenceKey {
    static var defaultValue: SectionMarkPreview? { nil }
    static func reduce(value: inout SectionMarkPreview?, nextValue: () -> SectionMarkPreview?) {
        value = nextValue() ?? value
    }
}
