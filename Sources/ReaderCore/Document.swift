import Foundation

public enum DocumentKind: String, Sendable, CaseIterable {
    case markdown, pdf, image, svg, json, table, text, unsupported

    public static let extensionsByKind: [DocumentKind: [String]] = [
        .markdown: ["md", "markdown", "mdown"],
        .pdf: ["pdf"],
        .svg: ["svg"],
        .image: ["png", "jpg", "jpeg", "gif", "heic", "heif", "tiff", "tif", "bmp", "webp", "icns"],
        .json: ["json", "geojson"],
        .table: ["csv", "tsv"],
        .text: ["txt", "log", "swift", "rs", "js", "jsx", "ts", "tsx", "py", "rb", "go",
                "c", "h", "cpp", "hpp", "m", "mm", "java", "kt", "sh", "zsh", "bash",
                "yaml", "yml", "toml", "xml", "html", "css", "scss", "sql", "ini", "conf",
                "gitignore", "env", "plist", "lock", "rst", "jsonc", "jsonl", "ndjson",
                "vue", "svelte", "less", "diff", "patch", "htm", "xhtml", "xcconfig",
                "config", "properties", "editorconfig", "bashrc", "zshrc", "fish",
                "cjs", "mjs", "cts", "mts", "cxx", "cc", "hxx", "hh", "cs", "kts",
                "php", "lua", "pl", "r", "graphql", "gql", "mk", "dockerfile", "dockerignore"]
    ]
    private static let kindsByExtension = Dictionary(uniqueKeysWithValues:
        extensionsByKind.flatMap { kind, extensions in extensions.map { ($0, kind) } })

    public init(url: URL) {
        self = Self.isDockerfile(url) || Self.isMakefile(url) || Self.isDockerignore(url) || Self.isEnvironment(url)
            ? .text : Self.kindsByExtension[url.pathExtension.lowercased()] ?? (url.pathExtension.isEmpty ? .text : .unsupported)
    }

    public static func isDockerfile(_ url: URL) -> Bool {
        let name = url.lastPathComponent.lowercased()
        let ext = url.pathExtension.lowercased()
        if name == "dockerfile" || ext == "dockerfile" { return true }
        guard name.hasPrefix("dockerfile."), ext != "dockerignore" else { return false }
        // A Dockerfile.md guide or Dockerfile.png image keeps its explicit format.
        return kindsByExtension[ext].map { $0 == .text } ?? true
    }

    public static func isMakefile(_ url: URL) -> Bool {
        let name = url.lastPathComponent.lowercased()
        let ext = url.pathExtension.lowercased()
        if name == "makefile" || name == "gnumakefile" || ext == "mk" { return true }
        guard name.hasPrefix("makefile.") else { return false }
        return kindsByExtension[ext].map { $0 == .text } ?? true
    }

    public static func isDockerignore(_ url: URL) -> Bool {
        url.lastPathComponent.lowercased() == ".dockerignore" || url.pathExtension.lowercased() == "dockerignore"
    }

    public static func isGitignore(_ url: URL) -> Bool {
        url.lastPathComponent.lowercased() == ".gitignore" || url.pathExtension.lowercased() == "gitignore"
    }

    public static func isEnvironment(_ url: URL) -> Bool {
        let name = url.lastPathComponent.lowercased()
        if name == ".env" || url.pathExtension.lowercased() == "env" { return true }
        guard name.hasPrefix(".env.") else { return false }
        return kindsByExtension[url.pathExtension.lowercased()].map { $0 == .text } ?? true
    }

    public var label: String {
        switch self {
        case .markdown: "Markdown"
        case .pdf: "PDF"
        case .image: "图片"
        case .svg: "SVG"
        case .json: "JSON"
        case .table: "表格"
        case .text: "纯文本"
        case .unsupported: "文件"
        }
    }

    public var symbol: String {
        switch self {
        case .markdown: "text.document"
        case .pdf: "doc.richtext"
        case .image: "photo"
        case .svg: "photo"
        case .json: "curlybraces"
        case .table: "tablecells"
        case .text: "chevron.left.forwardslash.chevron.right"
        case .unsupported: "doc"
        }
    }

    public var hasSource: Bool { [.markdown, .svg, .json, .table, .text].contains(self) }
}

public enum ReaderError: LocalizedError {
    case tooLarge(Int), notUTF8, binary, invalidCSV(String), tooManyRows, tooManyColumns

    public var errorDescription: String? {
        switch self {
        case .tooLarge(let limit): "文件超出当前预览上限（\(limit / 1_024 / 1_024) MB）。请在默认应用中打开。"
        case .notUTF8: "暂时只支持 UTF-8 文本。请转换编码后再打开。"
        case .binary: "这个文件包含二进制内容，无法作为文本预览。"
        case .invalidCSV(let reason): "表格格式错误：\(reason)"
        case .tooManyRows: "表格超过 10,000 行，请在表格应用中打开。"
        case .tooManyColumns: "表格超过 200 列，请在表格应用中打开。"
        }
    }
}

public struct FileEntry: Identifiable, Sendable, Equatable {
    public let url: URL
    public let isDirectory: Bool
    public var id: URL { url }
    public var name: String { url.lastPathComponent }
    public var kind: DocumentKind { DocumentKind(url: url) }

    public init(url: URL, isDirectory: Bool) {
        self.url = url
        self.isDirectory = isDirectory
    }
}

public enum FileReader {
    public static let textLimit = 4 * 1_024 * 1_024

    public static func text(at url: URL, limit: Int = textLimit) throws -> String {
        let file = try FileHandle(forReadingFrom: url)
        defer { try? file.close() }
        let data = try file.read(upToCount: limit + 1) ?? Data()
        guard data.count <= limit else { throw ReaderError.tooLarge(limit) }
        guard !data.contains(0) else { throw ReaderError.binary }
        guard var text = String(data: data, encoding: .utf8) else { throw ReaderError.notUTF8 }
        if text.hasPrefix("\u{FEFF}") { text.removeFirst() }
        return text
    }

    public static func children(of directory: URL) throws -> [FileEntry] {
        try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
            options: []
        ).map { url in
            let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            // Treat directory symlinks as files so expanding a tree can never cycle.
            return FileEntry(url: url, isDirectory: values.isDirectory == true && values.isSymbolicLink != true)
        }.sorted {
            if $0.isDirectory != $1.isDirectory { return $0.isDirectory }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }
}
