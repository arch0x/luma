import Foundation
import Testing
@testable import ReaderCore

struct FormatDetectionTests {
    @Test(arguments: [".env", ".env.local", ".env.production", ".env.example", "workspace.env", ".gitignore", "global.gitignore"])
    func environmentAndGitignoreNamesAreText(name: String) {
        let url = URL(fileURLWithPath: "/tmp/\(name)")
        #expect(DocumentKind(url: url) == .text)
        #expect(DocumentKind.isEnvironment(url) || DocumentKind.isGitignore(url))
    }
    @Test(arguments: ["Makefile", "makefile", "GNUmakefile", "Makefile.dev", "build.mk", ".dockerignore", "Dockerfile.dockerignore", "build.Dockerfile.dockerignore"])
    func makeAndIgnoreNamesAreRecognized(name: String) {
        let url = URL(fileURLWithPath: "/tmp/\(name)")
        #expect(DocumentKind(url: url) == .text)
        #expect(DocumentKind.isMakefile(url) || DocumentKind.isDockerignore(url))
        #expect(!DocumentKind.isDockerfile(url))
    }
    @Test(arguments: ["Dockerfile", "dockerfile", "DOCKERFILE", "Dockerfile.dev", "Dockerfile.prod", "build.Dockerfile"])
    func dockerfileNamesAreExplicitlyRecognizedAsText(name: String) {
        let url = URL(fileURLWithPath: "/tmp/\(name)")
        #expect(DocumentKind.isDockerfile(url) && DocumentKind(url: url) == .text)
    }

    @Test func dockerfilePrefixDoesNotOverrideDocumentsImagesOrIgnoreFiles() {
        #expect(DocumentKind(url: URL(fileURLWithPath: "/tmp/Dockerfile.md")) == .markdown)
        #expect(DocumentKind(url: URL(fileURLWithPath: "/tmp/Dockerfile.png")) == .image)
        #expect(!DocumentKind.isDockerfile(URL(fileURLWithPath: "/tmp/Dockerfile.dockerignore")))
    }
    @Test(arguments: ["jsonc", "jsonl", "ndjson", "vue", "svelte", "less", "diff", "patch", "mjs", "cts", "xcconfig"])
    func commonTextExtensionsAreEditable(ext: String) {
        #expect(DocumentKind(url: URL(fileURLWithPath: "/tmp/file.\(ext)")) == .text)
    }

    @Test func unknownTextKeepsEncodingNewlinesAndOriginalExtension() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID()).luma-custom")
        defer { try? FileManager.default.removeItem(at: file) }
        try Data("\u{FEFF}中文 🙂\r\nvalue = 42\r\n".utf8).write(to: file)
        let snapshot = try TextFileStore.read(at: file, detectingPlainText: true)
        #expect(snapshot.text == "中文 🙂\nvalue = 42\n" && snapshot.hasBOM && snapshot.newline == "\r\n")
        _ = try TextFileStore.save(snapshot.text + "edited\n", at: file, format: snapshot, expected: snapshot.version)
        #expect(try Data(contentsOf: file) == Data("\u{FEFF}中文 🙂\r\nvalue = 42\r\nedited\r\n".utf8))
        #expect(file.pathExtension == "luma-custom")
    }

    @Test(arguments: [
        Data([0x61, 0, 0x62]), Data([0x61, 0x01, 0x62]), Data([0xff, 0xfe, 0x61, 0]),
        Data([0xff, 0x61]), Data("%PDF-1.7".utf8), Data("bplist00example".utf8),
        Data("{\\rtf1 example}".utf8), Data([0x50, 0x4b, 0x05, 0x06])
    ])
    func unknownBinaryAndNonUTF8FilesAreRejected(data: Data) throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID()).luma-custom")
        defer { try? FileManager.default.removeItem(at: file) }
        try data.write(to: file)
        #expect(throws: (any Error).self) { try TextFileStore.read(at: file, detectingPlainText: true) }
        #expect(try Data(contentsOf: file) == data)
    }

    @Test(arguments: ["zip", "docx", "xlsx", "ttf", "sqlite", "png", "pdf"])
    func registeredBinaryFormatsDoNotUseTextFallback(ext: String) {
        #expect(!PlainTextFallback.permits(URL(fileURLWithPath: "/tmp/file.\(ext)")))
    }

    @Test(arguments: ["dat", "obj", "strings"])
    func registeredFormatsWithTextContentStillUseContentDetection(ext: String) throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID()).\(ext)")
        defer { try? FileManager.default.removeItem(at: file) }
        try Data("plain text\n中文".utf8).write(to: file)
        #expect(try TextFileStore.read(at: file, detectingPlainText: true).text == "plain text\n中文")
    }

    @Test func fallbackIsBoundedAndAllowsEmptyFilesAndOrdinaryWhitespace() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: file) }
        try Data().write(to: file)
        #expect(try TextFileStore.read(at: file, detectingPlainText: true).text == "")
        try Data("name\tvalue\n换行\r\n\u{c}".utf8).write(to: file)
        #expect(try TextFileStore.read(at: file, detectingPlainText: true).text.contains("换行"))
        try Data(repeating: 0x61, count: FileReader.textLimit + 1).write(to: file)
        #expect(throws: (any Error).self) { try TextFileStore.read(at: file, detectingPlainText: true) }
    }

    @Test func svgValidatesActualXMLAndKeepsSourceUntouched() throws {
        let source = #"<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 200 100"><text x="10" y="30">你好 &amp; Luma</text></svg>"#
        #expect(DocumentKind(url: URL(fileURLWithPath: "/tmp/IMAGE.SVG")) == .svg)
        try SVGDocument.validate(source)
        #expect(source.contains("&amp;"))
    }

    @Test(arguments: [
        "<svg", "<svg></svg>", #"<html xmlns="http://www.w3.org/2000/svg"/>"#,
        #"<svg xmlns="http://www.w3.org/2000/svg"><path></svg>"#,
        #"<!DOCTYPE svg SYSTEM "file:///etc/passwd"><svg xmlns="http://www.w3.org/2000/svg"/>"#,
        #"<!DOCTYPE svg [<!ENTITY a "expand">]><svg xmlns="http://www.w3.org/2000/svg">&a;</svg>"#
    ])
    func invalidOrEntityBearingSVGIsRejected(source: String) {
        #expect(throws: (any Error).self) { try SVGDocument.validate(source) }
    }

    @Test func svgPreviewHasItsOwnLimit() {
        let source = #"<svg xmlns="http://www.w3.org/2000/svg"><!--"# + String(repeating: "x", count: SVGDocument.previewLimit) + "--></svg>"
        #expect(throws: SVGDocument.SVGError.tooLarge) { try SVGDocument.validate(source) }
    }
}
