import Foundation
import SwiftUI
import ReaderCore

nonisolated struct CodeLanguage: Equatable, Sendable {
    let identifier: String
    let title: String
    var isJSONFamily: Bool { ["json", "jsonc", "jsonl", "ndjson"].contains(identifier) }

    init?(url: URL) {
        if DocumentKind.isDockerignore(url) {
            identifier = "dockerignore"; title = ".dockerignore"
            return
        }
        if DocumentKind.isMakefile(url) {
            identifier = "makefile"; title = "Makefile"
            return
        }
        if DocumentKind.isDockerfile(url) {
            identifier = "dockerfile"; title = "Dockerfile"
            return
        }
        if DocumentKind.isGitignore(url) {
            identifier = "gitignore"; title = ".gitignore"
            return
        }
        if DocumentKind.isEnvironment(url) {
            identifier = "dotenv"; title = ".env"
            return
        }
        let language: (String, String)
        switch url.pathExtension.lowercased() {
        case "json", "geojson": language = ("json", "JSON")
        case "jsonc": language = ("jsonc", "JSONC")
        case "jsonl": language = ("jsonl", "JSONL")
        case "ndjson": language = ("ndjson", "NDJSON")
        case "swift": language = ("swift", "Swift")
        case "py": language = ("python", "Python")
        case "js", "mjs", "cjs": language = ("javascript", "JavaScript")
        case "jsx": language = ("javascript", "JSX")
        case "ts", "mts", "cts": language = ("typescript", "TypeScript")
        case "tsx": language = ("typescript", "TSX")
        case "rs": language = ("rust", "Rust")
        case "go": language = ("go", "Go")
        case "rb": language = ("ruby", "Ruby")
        case "c", "h": language = ("c", "C")
        case "cpp", "hpp", "cc", "cxx", "hh", "hxx": language = ("cpp", "C++")
        case "cs": language = ("csharp", "C#")
        case "m", "mm": language = ("objectivec", "Objective-C")
        case "java": language = ("java", "Java")
        case "kt", "kts": language = ("kotlin", "Kotlin")
        case "sh", "bash", "zsh": language = ("bash", "Shell")
        case "yaml", "yml": language = ("yaml", "YAML")
        case "toml": language = ("ini", "TOML")
        case "ini": language = ("ini", "INI")
        case "xml", "plist": language = ("xml", "XML")
        case "html", "htm", "xhtml": language = ("xml", "HTML")
        case "vue": language = ("vue", "Vue")
        case "svelte": language = ("svelte", "Svelte")
        case "css": language = ("css", "CSS")
        case "scss": language = ("scss", "SCSS")
        case "less": language = ("less", "Less")
        case "diff", "patch": language = ("diff", "Diff")
        case "php": language = ("php", "PHP")
        case "lua": language = ("lua", "Lua")
        case "pl": language = ("perl", "Perl")
        case "r": language = ("r", "R")
        case "graphql", "gql": language = ("graphql", "GraphQL")
        case "mk": language = ("makefile", "Makefile")
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
    private var isJSON: Bool { tab.codeLanguage?.isJSONFamily == true }

    var body: some View {
        ZStack {
            MarkdownWebView(source: source, tab: tab, imageRoot: tab.url.deletingLastPathComponent(),
                            previewWidth: 0, typography: .init(), dark: colorScheme == .dark, state: state,
                            navigationRequest: 0, findRequest: 0, bookmarkRequest: 0, onOpen: { _ in })
                .opacity(state.error == nil ? 1 : 0)
            if state.loading {
                ProgressView(isJSON ? "正在格式化…" : "正在高亮…")
                    .padding().background(LumaTheme.chrome, in: RoundedRectangle(cornerRadius: 8))
            }
            if let error = state.error {
                VStack(spacing: 12) {
                    Text(isJSON ? "\(tab.formatLabel) 预览暂时不可用" : "代码预览暂时不可用").font(.headline)
                    Text(error).font(.caption).foregroundStyle(.secondary)
                    Button("查看源码") { tab.showSource = true }
                }.padding(24)
            }
        }
    }
}
