import Foundation
import ReaderCore
import AppKit
import ImageIO
import PDFKit
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
        let source = try #require(chineseWorkspace().samplesURL)
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
        let workspace = chineseWorkspace(preferences: preferences)
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

    @Test(arguments: InterfaceLanguage.allCases)
    func allNewExamplesOpenThroughTheActualWorkspace(language: InterfaceLanguage) async throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        let domain = "local.luma.sample-tests.\(UUID())"
        let preferences = try #require(UserDefaults(suiteName: domain))
        defer { preferences.removePersistentDomain(forName: domain) }
        let workspace = Workspace(preferences: preferences)
        workspace.language = language
        let source = try #require(workspace.samplesURL)
        let editable = directory.appendingPathComponent("Samples")
        try SampleWorkspace.install(from: source, to: editable)
        let formats = try SampleWorkspace.formats(language: language)
        let examples = formats.map { editable.appendingPathComponent($0.path) }
        #expect(examples.count == 67)
        workspace.open(examples)
        #expect(workspace.tabs.count == examples.count)
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
        let formats = try SampleWorkspace.formats(language: .simplifiedChinese)
        let actual = formats.flatMap(\.extensions)
        let expected = Set(DocumentKind.extensionsByKind.values.flatMap { $0 })
        #expect(Set(actual) == expected)
        #expect(actual.count == Set(actual).count, "An extension must not have duplicate examples")
        #expect(formats.count == Set(formats.map(\.path)).count)
        let samples = try #require(chineseWorkspace().samplesURL)
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
        #expect(project["sampleEdition"] as? String == SampleWorkspace.edition)
        #expect(SampleWorkspace.folderName != "Samples-0.8" && SampleWorkspace.folderName != "Samples-2026.11" && SampleWorkspace.folderName != "Samples-2026.11.1", "The new edition must not reuse an old editable copy")
    }

    @Test func everyImageExampleUsesItsRealCodecAndCanProduceAPreview() throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        let samples = try #require(chineseWorkspace().samplesURL)
        let expected = ["png": "public.png", "jpg": "public.jpeg", "gif": "com.compuserve.gif",
                        "heic": "public.heic", "tiff": "public.tiff", "bmp": "com.microsoft.bmp",
                        "webp": "org.webmproject.webp", "icns": "com.apple.icns"]
        for format in try SampleWorkspace.formats(language: .simplifiedChinese) where DocumentKind(url: samples.appendingPathComponent(format.path)) == .image {
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
        let samples = try #require(chineseWorkspace().samplesURL)
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
        #expect(matches.count >= (try SampleWorkspace.formats(language: .simplifiedChinese)).count)
        for match in matches {
            let range = try #require(Range(match.range(at: 1), in: guide))
            let reference = String(guide[range])
            let url = try #require(URL(string: reference, relativeTo: guideURL)?.absoluteURL)
            #expect(url.isFileURL && FileManager.default.fileExists(atPath: url.path), "Broken guide link: \(reference)")
        }
        for format in try SampleWorkspace.formats(language: .simplifiedChinese) { #expect(guide.contains(format.name)) }
        #expect(!FileManager.default.fileExists(atPath: samples.appendingPathComponent("格式示例/阅读卡片.svg").path))
        #expect(!FileManager.default.fileExists(atPath: samples.appendingPathComponent("格式示例/设置调整.patch").path))
    }
    @Test func newEditionLeavesOldFilesAndOpenDraftsUntouched() async throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        let domain = "local.luma.edition.\(UUID())"
        let preferences = try #require(UserDefaults(suiteName: domain))
        defer { preferences.removePersistentDomain(forName: domain) }
        let workspace = chineseWorkspace(preferences: preferences)
        let source = try #require(workspace.samplesURL)
        let oldFolder = directory.appendingPathComponent("Samples-2026.11.1")
        let newFolder = directory.appendingPathComponent(SampleWorkspace.folderName)
        try FileManager.default.createDirectory(at: oldFolder, withIntermediateDirectories: true)
        let oldWelcome = oldFolder.appendingPathComponent("欢迎.md")
        try "旧版已保存的笔记".write(to: oldWelcome, atomically: true, encoding: .utf8)
        workspace.open([oldWelcome])
        let oldTab = try #require(workspace.activeTab)
        await oldTab.loadTask?.value
        oldTab.edit("旧版尚未保存的草稿")
        try workspace.installAndOpenSamples(from: source, at: newFolder)
        #expect(try String(contentsOf: oldWelcome, encoding: .utf8) == "旧版已保存的笔记")
        #expect(workspace.tabs.contains { $0 === oldTab } && oldTab.isDirty && oldTab.draft == "旧版尚未保存的草稿")
        let newWelcome = newFolder.appendingPathComponent("欢迎.md")
        let newText = try String(contentsOf: newWelcome, encoding: .utf8)
        #expect(newText.contains(SampleWorkspace.edition) && newText.contains("解释所选值"))
        try "新版用户自己的笔记".write(to: newWelcome, atomically: true, encoding: .utf8)
        try SampleWorkspace.install(from: source, to: newFolder)
        #expect(try String(contentsOf: newWelcome, encoding: .utf8) == "新版用户自己的笔记")
    }

    @Test func newExamplesExerciseFiltersNumericSortAndValueInterpretation() throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = try #require(chineseWorkspace().samplesURL)
        let csvURL = source.appendingPathComponent("阅读清单.csv")
        let before = try Data(contentsOf: csvURL)
        let table = try CSVDocument(String(decoding: before, as: UTF8.self))
        let columns = try #require(table.rows.first)
        let status = try #require(columns.firstIndex(of: "状态"))
        let pages = try #require(columns.firstIndex(of: "页数"))
        let reading = TableReadingState(); reading.update(table)
        reading.setFilter(.init(values: ["待阅读"]), column: status)
        #expect(reading.visibleRows.count == 2)
        reading.reset(); reading.sort(column: pages, ascending: true)
        #expect(reading.visibleRows.map { reading.value(row: $0, column: pages) } == ["2", "5", "12", "120", ""])
        #expect(table.rows[1].last?.contains("\n") == true && table.sourceLines[2] == 4)
        #expect(try Data(contentsOf: csvURL) == before)

        let project = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: source.appendingPathComponent("项目.json"))) as? [String: Any])
        let examples = try #require(project["inspectionExamples"] as? [String: Any])
        let color = try #require(examples["colorWithAlpha"] as? String)
        #expect(try #require(ReadableValue.color(color)).alpha < 1)
        let seconds = try #require(examples["timestampSeconds"] as? NSNumber)
        let milliseconds = try #require(examples["timestampMilliseconds"] as? NSNumber)
        let first = try #require(ReadableValue.date(seconds.stringValue, unit: .seconds))
        let second = try #require(ReadableValue.date(milliseconds.stringValue, unit: .milliseconds))
        #expect(abs(second.timeIntervalSince(first) - 0.123) < 0.001)
        #expect(ReadableValue.byteCount(try #require(examples["sizeWithUnit"] as? String)) == (examples["byteCount"] as? NSNumber)?.doubleValue)
        let text = try #require(examples["escapedText"] as? String)
        #expect(text.contains("\n") && text.contains("\t"))
        #expect(ReadableValue.decodedString(ReadableValue.encodeString(text)) == text)
    }

}
