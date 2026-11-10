import SwiftUI

struct MarkdownBookmarksView: View {
    let session: MarkdownReadingSession
    let addTitle: String
    let adding: Bool
    let onAdd: () -> Void
    let onSelect: (MarkdownReadingLocation) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 4) {
                Text(session.bookmarks.isEmpty ? tr("书签") : tr("书签 · \(session.bookmarks.count)"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(LumaTheme.muted)
                Spacer(minLength: 4)
                Button(action: onAdd) { Label(addTitle, systemImage: "bookmark.badge.plus") }
                    .buttonStyle(LumaButtonStyle())
                    .disabled(adding || session.bookmarks.count >= 500)
            }
            .padding(.horizontal, 8)
            .frame(height: 38)

            if !session.bookmarks.isEmpty {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(session.bookmarks) { bookmark in
                            HStack(spacing: 2) {
                                Button { onSelect(bookmark.location) } label: {
                                    Text(bookmark.title)
                                        .lineLimit(1).truncationMode(.tail)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .buttonStyle(LumaButtonStyle())
                                .help(bookmark.title)
                                Button { session.removeBookmark(bookmark.id) } label: {
                                    Image(systemName: "trash")
                                }
                                .buttonStyle(LumaButtonStyle())
                                .help(tr("移除书签")).accessibilityLabel(tr("移除 \(bookmark.title)"))
                            }
                            .padding(.horizontal, 8).frame(height: 32)
                        }
                    }
                }
                .frame(height: CGFloat(min(3, session.bookmarks.count)) * 32)
            }
        }
    }
}
