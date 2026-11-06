import SwiftUI

struct MarkdownBookmarksView: View {
    @Bindable var session: MarkdownReadingSession
    let adding: Bool
    let onAdd: () -> Void
    let onSelect: (MarkdownReadingLocation) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("此文档的书签").font(.headline)
                Spacer()
                Button(action: onAdd) { Label("添加当前位置", systemImage: "bookmark.badge.plus") }
                    .disabled(adding || session.bookmarks.count >= 500)
            }.padding(16)
            Divider()
            if session.bookmarks.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "bookmark").font(.title2).foregroundStyle(.tertiary)
                    Text("把想回看的位置留在这里。")
                        .font(.callout).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity).padding(.vertical, 34)
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(session.bookmarks) { bookmark in
                            HStack(spacing: 8) {
                                Button { onSelect(bookmark.location) } label: {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(bookmark.title).font(.system(size: 12, weight: .medium)).lineLimit(2)
                                        Text("保存时进度 \(Int(bookmark.location.progress * 100))%")
                                            .font(.system(size: 10)).foregroundStyle(.secondary)
                                    }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 9).contentShape(Rectangle())
                                }.buttonStyle(.plain)
                                Button { session.removeBookmark(bookmark.id) } label: {
                                    Image(systemName: "trash").foregroundStyle(.secondary).frame(width: 24, height: 28)
                                }.buttonStyle(.plain).help("移除书签").accessibilityLabel("移除 \(bookmark.title)")
                            }.padding(.horizontal, 16)
                        }
                    }.padding(.vertical, 6)
                }.frame(maxHeight: 340)
            }
        }.frame(width: 360)
    }
}
