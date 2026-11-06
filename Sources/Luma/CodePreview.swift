import Foundation
import SwiftUI

nonisolated struct CodeLanguage: Equatable, Sendable {
    let identifier: String
    let title: String

    init?(url: URL) {
        let language: (String, String)
        switch url.pathExtension.lowercased() {
        case "json", "geojson": language = ("json", "JSON")
        case "swift": language = ("swift", "Swift")
        case "py": language = ("python", "Python")
        case "js": language = ("javascript", "JavaScript")
        case "jsx": language = ("javascript", "JSX")
        case "ts": language = ("typescript", "TypeScript")
        case "tsx": language = ("typescript", "TSX")
        case "rs": language = ("rust", "Rust")
        case "go": language = ("go", "Go")
        case "rb": language = ("ruby", "Ruby")
        case "c", "h": language = ("c", "C")
        case "cpp", "hpp": language = ("cpp", "C++")
        case "m", "mm": language = ("objectivec", "Objective-C")
        case "java": language = ("java", "Java")
        case "kt": language = ("kotlin", "Kotlin")
        case "sh", "bash", "zsh": language = ("bash", "Shell")
        case "yaml", "yml": language = ("yaml", "YAML")
        case "toml": language = ("ini", "TOML")
        case "ini": language = ("ini", "INI")
        case "xml", "plist": language = ("xml", "XML")
        case "html": language = ("xml", "HTML")
        case "css": language = ("css", "CSS")
        case "scss": language = ("scss", "SCSS")
        case "sql": language = ("sql", "SQL")
        default: return nil
        }
        identifier = language.0
        title = language.1
    }
}

/// Uses the bundled highlighter and color palette, without Markdown parsing of code.
struct CodePreview: View {
    let source: String
    let tab: DocumentTab
    @Environment(\.colorScheme) private var colorScheme
    @ViewState private var state = MarkdownRenderState()

    var body: some View {
        ZStack {
            MarkdownWebView(source: source, tab: tab, imageRoot: tab.url.deletingLastPathComponent(),
                            previewWidth: 0, typography: .init(), dark: colorScheme == .dark, state: state,
                            navigationRequest: 0, findRequest: 0, bookmarkRequest: 0, onOpen: { _ in })
                .opacity(state.error == nil ? 1 : 0)
            if state.loading {
                ProgressView(tab.kind == .json ? "正在格式化…" : "正在高亮…").padding().background(.regularMaterial, in: RoundedRectangle(cornerRadius: 9))
            }
            if let error = state.error {
                VStack(spacing: 12) {
                    Text(tab.kind == .json ? "JSON 预览暂时不可用" : "代码预览暂时不可用").font(.headline)
                    Text(error).font(.caption).foregroundStyle(.secondary)
                    Button("查看源码") { tab.showSource = true }
                }.padding(24)
            }
        }
    }
}
