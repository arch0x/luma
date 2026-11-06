import Foundation
import Testing
@testable import ReaderCore

struct FileCreationTests {
    let directory: URL
    init() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }
    private func clean() { try? FileManager.default.removeItem(at: directory) }

    @Test(arguments: ["笔记.md", "阅读 计划.txt", "100% #1.json", "README", ".env", "  note.md  "])
    func createsEmptyFilesWithExactNames(name: String) throws {
        defer { clean() }
        let file = try FileCreator.createEmptyFile(named: name, in: directory)
        #expect(file.deletingLastPathComponent().path == directory.resolvingSymlinksInPath().path)
        #expect(file.lastPathComponent == name.trimmingCharacters(in: .whitespacesAndNewlines))
        #expect(try Data(contentsOf: file).isEmpty)
    }

    @Test(arguments: ["", "   ", ".", "..", "../escape.md", "/tmp/escape", "child/note.md", "bad:name", "bad\0name", "bad\nname", "\nnote"])
    func invalidNamesDoNotCreateAnything(name: String) throws {
        defer { clean() }
        #expect(throws: FileCreationError.invalidName) {
            try FileCreator.createEmptyFile(named: name, in: directory)
        }
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty)
    }

    @Test func nameCollisionsPreserveFilesDirectoriesAndSymbolicLinks() throws {
        defer { clean() }
        let original = directory.appendingPathComponent("original.md")
        try Data("existing content".utf8).write(to: original)
        let subfolder = directory.appendingPathComponent("folder")
        try FileManager.default.createDirectory(at: subfolder, withIntermediateDirectories: false)
        let link = directory.appendingPathComponent("link.md")
        let dangling = directory.appendingPathComponent("dangling.md")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: original)
        try FileManager.default.createSymbolicLink(at: dangling, withDestinationURL: directory.appendingPathComponent("missing.md"))
        for name in ["original.md", "folder", "link.md", "dangling.md"] {
            #expect(throws: FileCreationError.alreadyExists(name)) {
                try FileCreator.createEmptyFile(named: name, in: directory)
            }
        }
        #expect(try String(contentsOf: original, encoding: .utf8) == "existing content")
        #expect(try subfolder.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true)
        #expect(try link.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink == true)
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: dangling.path).hasSuffix("missing.md"))
        #expect(!FileManager.default.fileExists(atPath: directory.appendingPathComponent("missing.md").path))
    }

    @Test func competingCreationsHaveExactlyOneWinner() async throws {
        defer { clean() }
        let directory = directory
        let successes = await withTaskGroup(of: Int.self) { group in
            for _ in 0..<16 {
                group.addTask {
                    do { _ = try FileCreator.createEmptyFile(named: "race.md", in: directory); return 1 }
                    catch { return 0 }
                }
            }
            var successes = 0
            for await count in group { successes += count }
            return successes
        }
        #expect(successes == 1)
        #expect(try Data(contentsOf: directory.appendingPathComponent("race.md")).isEmpty)
    }

    @Test func missingNonDirectoryAndUnwritableTargetsFail() throws {
        defer { clean() }
        let file = directory.appendingPathComponent("plain.txt")
        try Data("keep".utf8).write(to: file)
        #expect(throws: FileCreationError.notDirectory) {
            try FileCreator.createEmptyFile(named: "new.md", in: file)
        }
        #expect(throws: (any Error).self) {
            try FileCreator.createEmptyFile(named: "new.md", in: directory.appendingPathComponent("missing"))
        }
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: directory.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: directory.path) }
        #expect(throws: (any Error).self) {
            try FileCreator.createEmptyFile(named: "new.md", in: directory)
        }
        #expect(try String(contentsOf: file, encoding: .utf8) == "keep")
        #expect(!FileManager.default.fileExists(atPath: directory.appendingPathComponent("new.md").path))
    }
    @Test func createsFolderWithoutReusingExistingItems() throws {
        defer { clean() }
        let folder = try FileCreator.createDirectory(named: "项目 资料", in: directory)
        #expect(try folder.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true)
        let original = folder.appendingPathComponent("keep.txt")
        try "keep".write(to: original, atomically: true, encoding: .utf8)
        #expect(throws: FileCreationError.alreadyExists("项目 资料")) {
            try FileCreator.createDirectory(named: "项目 资料", in: directory)
        }
        #expect(try String(contentsOf: original, encoding: .utf8) == "keep")
        try "file".write(to: directory.appendingPathComponent("name"), atomically: true, encoding: .utf8)
        #expect(throws: FileCreationError.alreadyExists("name")) {
            try FileCreator.createDirectory(named: "name", in: directory)
        }
        #expect(throws: FileCreationError.invalidName) {
            try FileCreator.createDirectory(named: "../escape", in: directory)
        }
        let link = directory.appendingPathComponent("folder-link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: folder)
        #expect(throws: FileCreationError.alreadyExists("folder-link")) {
            try FileCreator.createDirectory(named: "folder-link", in: directory)
        }
    }

    @Test func concurrentFolderCreationHasOneWinner() async throws {
        defer { clean() }
        let directory = directory
        let successes = await withTaskGroup(of: Int.self) { group in
            for _ in 0..<16 {
                group.addTask {
                    do { _ = try FileCreator.createDirectory(named: "同名目录", in: directory); return 1 }
                    catch { return 0 }
                }
            }
            var successes = 0
            for await count in group { successes += count }
            return successes
        }
        #expect(successes == 1)
    }

}
