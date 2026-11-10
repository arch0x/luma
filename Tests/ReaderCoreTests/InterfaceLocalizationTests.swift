import Foundation
import Testing
@testable import ReaderCore

@Suite(.serialized) struct InterfaceLocalizationTests {
    @Test func rendersUserValuesWithoutTreatingThemAsTemplateTokens() {
        let name = "中文{1}%s🙂.md"
        let message: InterfaceMessage = "将“\(name)”移到废纸篓？"
        #expect(ReaderLocalization.text(message, language: .english) == "Move “\(name)” to Trash?")
        #expect(ReaderLocalization.text(message, language: .simplifiedChinese) == "将“\(name)”移到废纸篓？")
        let count: InterfaceMessage = "\(2) / \(5) 条 · \(3) 列"
        #expect(ReaderLocalization.text(count, language: .english) == "2 / 5 records · 3 columns")
        let height: InterfaceMessage = "\(1.85, specifier: "%.2f") 倍"
        #expect(ReaderLocalization.text(height, language: .english) == "1.85×")
    }
    @Test func readerErrorsUseTheSelectedLanguageAndKeepFilenames() {
        let previous = ReaderLocalization.language
        defer { ReaderLocalization.language = previous }
        ReaderLocalization.language = .english
        #expect(ReaderError.notUTF8.errorDescription?.contains("UTF-8 text") == true)
        #expect(FileCreationError.alreadyExists("原始文件.md").errorDescription?.contains("原始文件.md") == true)
        #expect(DocumentKind.image.label == "Image")
        ReaderLocalization.language = .simplifiedChinese
        #expect(DocumentKind.image.label == "图片")
    }
    @Test func everyCanonicalTranslationIsAvailableInBothNativeBundles() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let translations = try JSONDecoder().decode([String: String].self, from: Data(contentsOf: root.appendingPathComponent("Localization/en.json")))
        for (key, english) in translations {
            #expect(ReaderLocalization.text(key: key, language: .english) == english, "Missing English resource: \(key)")
            #expect(ReaderLocalization.text(key: key, language: .simplifiedChinese) == key, "Missing Chinese resource: \(key)")
        }
        #expect(ReaderLocalization.text(key: "Unknown key", language: .english) == "Unknown key")
    }
}
