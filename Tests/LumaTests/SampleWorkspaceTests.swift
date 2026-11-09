import Foundation
import ReaderCore
import AppKit
import ImageIO
import Testing
@testable import Luma

@MainActor struct SampleWorkspaceTests {
    let directory: URL

    init() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    @Test func existingSamplesGetMissingFilesWithoutLosingEdits() throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = try #require(Workspace().samplesURL)
        let editable = directory.appendingPathComponent("Samples")
        try FileManager.default.createDirectory(at: editable, withIntermediateDirectories: true)
        let welcome = editable.appendingPathComponent("欢迎.md")
        try Data("我的欢迎页".utf8).write(to: welcome)
        try SampleWorkspace.install(from: source, to: editable)
        let guide = editable.appendingPathComponent("格式示例/格式导览.md")
        #expect(FileManager.default.fileExists(atPath: guide.path))
        #expect(try String(contentsOf: welcome, encoding: .utf8) == "我的欢迎页")
        try Data("我改过的导览".utf8).write(to: guide)
        let missing = editable.appendingPathComponent("格式示例/阅读设置.jsonc")
        try FileManager.default.removeItem(at: missing)
        try SampleWorkspace.install(from: source, to: editable)
        #expect(FileManager.default.fileExists(atPath: missing.path))
        #expect(try String(contentsOf: guide, encoding: .utf8) == "我改过的导览")
        #expect(try String(contentsOf: welcome, encoding: .utf8) == "我的欢迎页")
    }

    @Test func sampleUpgradePreservesNameCollisionsAndDoesNotFollowUserSymlinks() throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("bundled")
        let editable = directory.appendingPathComponent("editable")
        let outside = directory.appendingPathComponent("outside")
        for folder in [source, editable, outside] { try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true) }
        try FileManager.default.createDirectory(at: source.appendingPathComponent("formats"), withIntermediateDirectories: true)
        try Data("new example".utf8).write(to: source.appendingPathComponent("formats/new.txt"))
        try Data("bundled file".utf8).write(to: source.appendingPathComponent("note.txt"))
        try FileManager.default.createSymbolicLink(at: editable.appendingPathComponent("formats"), withDestinationURL: outside)
        try FileManager.default.createDirectory(at: editable.appendingPathComponent("note.txt"), withIntermediateDirectories: true)
        try SampleWorkspace.install(from: source, to: editable)
        #expect(try FileManager.default.contentsOfDirectory(atPath: outside.path).isEmpty)
        #expect(try editable.appendingPathComponent("formats").resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink == true)
        #expect(try editable.appendingPathComponent("note.txt").resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true)
    }

    @Test func reopeningSamplesRefreshesCachedFoldersAndKeepsTheOpenDraft() async throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        let domain = "local.luma.sample-refresh.\(UUID())"
        let preferences = try #require(UserDefaults(suiteName: domain))
        defer { preferences.removePersistentDomain(forName: domain) }
        let workspace = Workspace(preferences: preferences)
        let bundled = try #require(workspace.samplesURL)
        let editable = directory.appendingPathComponent("Samples").resolvingSymlinksInPath().standardizedFileURL
        let formats = editable.appendingPathComponent("格式示例")
        try FileManager.default.createDirectory(at: formats, withIntermediateDirectories: true)
        let welcome = editable.appendingPathComponent("欢迎.md")
        try Data("我的欢迎页".utf8).write(to: welcome)
        workspace.roots = [editable]
        workspace.expanded = [editable, formats]
        workspace.directories[editable] = [FileEntry(url: welcome, isDirectory: false)]
        workspace.directories[formats] = []
        workspace.open([welcome])
        let tab = try #require(workspace.activeTab)
        await tab.loadTask?.value
        tab.edit("还未保存的笔记")
        try workspace.installAndOpenSamples(from: bundled, at: editable)
        let deadline = ContinuousClock.now + .seconds(5)
        while !workspace.loadingDirectories.isEmpty && ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(20)) }
        #expect(workspace.loadingDirectories.isEmpty)
        #expect(workspace.directories[editable]?.contains { $0.name == "格式示例" } == true)
        #expect(workspace.directories[formats]?.contains { $0.name == "阅读设置.jsonc" } == true)
        #expect(workspace.activeTab === tab && tab.isDirty && tab.draft == "还未保存的笔记")
        #expect(try String(contentsOf: welcome, encoding: .utf8) == "我的欢迎页")
    }

    @Test func allNewExamplesOpenThroughTheActualWorkspace() async throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        let domain = "local.luma.sample-tests.\(UUID())"
        let preferences = try #require(UserDefaults(suiteName: domain))
        defer { preferences.removePersistentDomain(forName: domain) }
        let workspace = Workspace(preferences: preferences)
        let source = try #require(workspace.samplesURL)
        let editable = directory.appendingPathComponent("Samples")
        try SampleWorkspace.install(from: source, to: editable)
        let formats = try SampleWorkspace.formats()
        let examples = formats.map { editable.appendingPathComponent($0.path) }
        workspace.open(examples)
        for tab in workspace.tabs {
            await tab.loadTask?.value
            if case .ready(.failed(let error)) = tab.state { Issue.record("\(tab.title): \(error)") }
            #expect(tab.canEdit == tab.kind.hasSource && tab.previewError == nil, "Failed to load \(tab.title)")
            if tab.url.pathExtension == "svg" {
                guard case .ready(.svg) = tab.state else { Issue.record("SVG sample has no preview"); continue }
            }
            if ["jsonl", "ndjson"].contains(tab.url.pathExtension) {
                for line in try #require(tab.draft).split(separator: "\n") {
                    _ = try JSONSerialization.jsonObject(with: Data(line.utf8))
                }
            }
            if tab.url.pathExtension == "luma-note" { #expect(tab.kind == .text && !tab.hasPreview) }
        }
    }

    @Test func catalogCoversEveryRecognizedExtensionWithUniqueRepresentatives() throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        let formats = try SampleWorkspace.formats()
        let actual = formats.flatMap(\.extensions)
        let expected = Set(DocumentKind.extensionsByKind.values.flatMap { $0 })
        #expect(Set(actual) == expected)
        #expect(actual.count == Set(actual).count, "An extension must not have duplicate examples")
        #expect(formats.count == Set(formats.map(\.path)).count)
        let samples = try #require(Workspace().samplesURL)
        for format in formats {
            let url = samples.appendingPathComponent(format.path)
            #expect(FileManager.default.fileExists(atPath: url.path), "Missing \(format.name): \(format.path)")
            let ext = DocumentKind.isMakefile(url) ? "mk" : DocumentKind.isDockerfile(url) ? "dockerfile" : url.pathExtension.isEmpty && url.lastPathComponent.hasPrefix(".")
                ? String(url.lastPathComponent.dropFirst()) : url.pathExtension
            #expect(format.extensions.isEmpty || format.extensions.contains(ext), "Wrong representative for \(format.name)")
        }
        let project = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: samples.appendingPathComponent("项目.json"))) as? [String: Any])
        let workspace = try #require(project["workspace"] as? [String: Any])
        #expect(workspace["representativeFormats"] as? Int == formats.count)
        #expect(SampleWorkspace.folderName != "Samples-0.8", "The blue edition must not reuse an old editable copy")
    }

    @Test func everyImageExampleUsesItsRealCodecAndCanProduceAPreview() throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        let samples = try #require(Workspace().samplesURL)
        let expected = ["png": "public.png", "jpg": "public.jpeg", "gif": "com.compuserve.gif",
                        "heic": "public.heic", "tiff": "public.tiff", "bmp": "com.microsoft.bmp",
                        "webp": "org.webmproject.webp", "icns": "com.apple.icns"]
        for format in try SampleWorkspace.formats() where DocumentKind(url: samples.appendingPathComponent(format.path)) == .image {
            let url = samples.appendingPathComponent(format.path)
            let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil), "Cannot decode \(format.path)")
            #expect(CGImageSourceGetType(source) as String? == expected[url.pathExtension])
            let image = try #require(CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: 128
            ] as CFDictionary), "Cannot preview \(format.path)")
            #expect(image.width > 0 && image.height > 0)
        }
    }

    @Test func coverPaletteAndGuideLinksMatchTheBlueEdition() throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        let samples = try #require(Workspace().samplesURL)
        let bitmap = try #require(NSBitmapImageRep(data: Data(contentsOf: samples.appendingPathComponent("留白.png"))))
        var blue = 0, green = 0
        for y in stride(from: 0, to: bitmap.pixelsHigh, by: 8) {
            for x in stride(from: 0, to: bitmap.pixelsWide, by: 8) {
                let color = try #require(bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB))
                if color.blueComponent > color.redComponent + 0.06 && color.blueComponent > color.greenComponent + 0.03 { blue += 1 }
                if color.greenComponent > color.redComponent + 0.08 && color.greenComponent > color.blueComponent + 0.03 { green += 1 }
            }
        }
        #expect(blue > 100 && green == 0, "The checked-in PNG must use blue instead of the legacy green")
        let guideURL = samples.appendingPathComponent("格式示例/格式导览.md")
        let guide = try String(contentsOf: guideURL, encoding: .utf8)
        let expression = try NSRegularExpression(pattern: #"\]\(<?([^\n)>]+)>?\)"#)
        let matches = expression.matches(in: guide, range: NSRange(guide.startIndex..., in: guide))
        #expect(matches.count >= (try SampleWorkspace.formats()).count)
        for match in matches {
            let range = try #require(Range(match.range(at: 1), in: guide))
            let reference = String(guide[range])
            let url = try #require(URL(string: reference, relativeTo: guideURL)?.absoluteURL)
            #expect(url.isFileURL && FileManager.default.fileExists(atPath: url.path), "Broken guide link: \(reference)")
        }
        for format in try SampleWorkspace.formats() { #expect(guide.contains(format.name)) }
        #expect(!FileManager.default.fileExists(atPath: samples.appendingPathComponent("格式示例/阅读卡片.svg").path))
        #expect(!FileManager.default.fileExists(atPath: samples.appendingPathComponent("格式示例/设置调整.patch").path))
    }
}
