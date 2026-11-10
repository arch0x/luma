import Foundation
import PDFKit
import ReaderCore
import Testing
@testable import Luma

@MainActor struct BilingualSamplesTests {
    @Test func openingBothLanguagesKeepsCopiesAndDraftsIndependent() async throws {
        let domain = "local.luma.bilingual-samples.\(UUID())"
        let preferences = try #require(UserDefaults(suiteName: domain))
        let previous = AppLocalization.shared.language
        let parent = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer {
            preferences.removePersistentDomain(forName: domain)
            AppLocalization.shared.language = previous
            try? FileManager.default.removeItem(at: parent)
        }
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        let workspace = Workspace(preferences: preferences)
        #expect(workspace.language == .english)
        var copies: [URL] = []
        var tabs: [DocumentTab] = []
        for language in InterfaceLanguage.allCases {
            workspace.language = language
            let source = try #require(workspace.samplesURL)
            #expect(source.lastPathComponent == language.rawValue)
            let copy = parent.appendingPathComponent(SampleWorkspace.folderName(for: language))
            try workspace.installAndOpenSamples(from: source, at: copy)
            let tab = try #require(workspace.activeTab)
            await tab.loadTask?.value
            #expect(tab.title == SampleWorkspace.welcomeFilename(for: language))
            let original = try #require(tab.draft)
            #expect(original.contains(SampleWorkspace.edition))
            tab.edit(original + "\nUnsaved personal note: \(language.rawValue)\n")
            copies.append(copy); tabs.append(tab)
        }
        #expect(copies[0] != copies[1] && tabs[0] !== tabs[1])
        for (index, language) in InterfaceLanguage.allCases.enumerated() {
            workspace.language = language
            let source = try #require(workspace.samplesURL)
            let tab = tabs[index]
            let draft = tab.draft
            try workspace.installAndOpenSamples(from: source, at: copies[index])
            #expect(workspace.activeTab === tab && tab.isDirty && tab.draft == draft)
            let disk = try String(contentsOf: tab.url, encoding: .utf8)
            #expect(!disk.contains("Unsaved personal note"))
        }
        #expect(workspace.tabs.count == 2)
    }

    @Test(arguments: InterfaceLanguage.allCases)
    func catalogGuideMetadataAndPDFMatchLanguage(language: InterfaceLanguage) throws {
        let source = try #require(Workspace().samplesURL(for: language))
        let formats = try SampleWorkspace.formats(language: language)
        #expect(Set(formats.flatMap(\.extensions)) == Set(DocumentKind.extensionsByKind.values.flatMap { $0 }))
        #expect(formats.count == 67 && Set(formats.map(\.path)).count == 67)
        let english = language == .english
        let projectURL = source.appendingPathComponent(english ? "Project.json" : "项目.json")
        let project = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: projectURL)) as? [String: Any])
        #expect(project["sampleEdition"] as? String == SampleWorkspace.edition)
        let guideURL = source.appendingPathComponent(english ? "FormatExamples/FormatGuide.md" : "格式示例/格式导览.md")
        let guide = try String(contentsOf: guideURL, encoding: .utf8)
        for format in formats {
            #expect(FileManager.default.fileExists(atPath: source.appendingPathComponent(format.path).path))
            #expect(guide.contains(format.name))
            #expect(guide.contains("[\(URL(fileURLWithPath: format.path).lastPathComponent)]"))
        }
        let links = try NSRegularExpression(pattern: #"\]\(<?([^\n)>]+)>?\)"#)
        for match in links.matches(in: guide, range: NSRange(guide.startIndex..., in: guide)) {
            let range = try #require(Range(match.range(at: 1), in: guide))
            let url = try #require(URL(string: String(guide[range]), relativeTo: guideURL)?.absoluteURL)
            #expect(url.isFileURL && FileManager.default.fileExists(atPath: url.path))
        }
        let pdf = try #require(PDFDocument(url: source.appendingPathComponent(english ? "ReadingSpace.pdf" : "阅读空间.pdf")))
        #expect(pdf.pageCount == 2)
        #expect(pdf.string?.contains(english ? "clarity" : "清楚") == true)
        if english {
            let enumerator = try #require(FileManager.default.enumerator(at: source, includingPropertiesForKeys: [.isRegularFileKey]))
            for case let file as URL in enumerator {
                guard try file.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true,
                      let text = try? String(contentsOf: file, encoding: .utf8) else { continue }
                #expect(text.range(of: #"[\p{Han}]"#, options: .regularExpression) == nil, "Untranslated English fixture: \(file.lastPathComponent)")
            }
        }
    }
}
