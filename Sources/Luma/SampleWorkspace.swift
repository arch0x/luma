import Foundation
import ReaderCore

nonisolated enum SampleWorkspace {
    static let edition = "2026.11.3"
    static var folderName: String { folderName(for: .english) }

    static func folderName(for language: InterfaceLanguage) -> String { "Samples-\(edition)-\(language.rawValue)" }
    static func welcomeFilename(for language: InterfaceLanguage) -> String { language == .english ? "Welcome.md" : "欢迎.md" }

    nonisolated struct Format: Decodable {
        let name: String
        let extensions: [String]
        let path: String
        let section: String
    }

    static func formats(language: InterfaceLanguage = .english) throws -> [Format] {
        guard let url = Bundle.module.url(forResource: "SampleCatalog-\(language.rawValue)", withExtension: "json") else {
            throw CocoaError(.fileReadNoSuchFile)
        }
        return try JSONDecoder().decode([Format].self, from: Data(contentsOf: url))
    }

    /// Adds bundled examples without replacing anything in the user's editable copy.
    static func install(from source: URL, to destination: URL) throws {
        let manager = FileManager.default
        guard let destinationType = try type(at: destination) else {
            try manager.copyItem(at: source, to: destination)
            return
        }
        guard destinationType == .typeDirectory else { throw CocoaError(.fileWriteFileExists) }

        for item in try manager.contentsOfDirectory(at: source, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey]) {
            let target = destination.appendingPathComponent(item.lastPathComponent)
            let targetType = try type(at: target)
            if targetType == nil {
                try manager.copyItem(at: item, to: target)
            } else if targetType == .typeDirectory {
                let values = try item.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
                if values.isDirectory == true && values.isSymbolicLink != true {
                    try install(from: item, to: target)
                }
            }
        }
    }

    private static func type(at url: URL) throws -> FileAttributeType? {
        do { return try FileManager.default.attributesOfItem(atPath: url.path)[.type] as? FileAttributeType }
        catch let error as CocoaError where error.code == .fileNoSuchFile || error.code == .fileReadNoSuchFile { return nil }
    }
}
