import Foundation
import Testing
@testable import ReaderCore

struct HiddenFilesTests {
    @Test func directoryListsDotFilesDotFoldersAndFinderHiddenItems() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        for name in [".env", ".gitignore", "visible.txt", "finder-hidden.txt"] {
            try "text".write(to: directory.appendingPathComponent(name), atomically: true, encoding: .utf8)
        }
        let folder = directory.appendingPathComponent(".config", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        var hidden = directory.appendingPathComponent("finder-hidden.txt")
        var values = URLResourceValues(); values.isHidden = true
        try hidden.setResourceValues(values)
        let entries = try FileReader.children(of: directory)
        #expect(Set(entries.map(\.name)) == [".env", ".gitignore", "visible.txt", "finder-hidden.txt", ".config"])
        #expect(entries.first?.name == ".config" && entries.first?.isDirectory == true)
        #expect(DocumentKind(url: directory.appendingPathComponent(".env")) == .text)
    }
}
