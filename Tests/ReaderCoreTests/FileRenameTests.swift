import Foundation
import Testing
@testable import ReaderCore

struct FileRenameTests {
    let directory: URL
    init() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }
    private func clean() { try? FileManager.default.removeItem(at: directory) }

    @Test(arguments: [false, true])
    func renamesFilesAndFoldersWithContentsAndMetadataIntact(folder: Bool) throws {
        defer { clean() }
        let source = directory.appendingPathComponent("original")
        if folder { try FileManager.default.createDirectory(at: source, withIntermediateDirectories: false) }
        let file = folder ? source.appendingPathComponent("child.txt") : source
        try "original bytes".write(to: file, atomically: true, encoding: .utf8)
        let before = try FileManager.default.attributesOfItem(atPath: file.path)[.systemFileNumber] as? NSNumber
        let renamed = try FileRenamer.rename(source, to: "新名称 100%")
        let movedFile = folder ? renamed.appendingPathComponent("child.txt") : renamed
        #expect(!FileManager.default.fileExists(atPath: source.path))
        #expect(try String(contentsOf: movedFile, encoding: .utf8) == "original bytes")
        #expect(try FileManager.default.attributesOfItem(atPath: movedFile.path)[.systemFileNumber] as? NSNumber == before)
        #expect(renamed.hasDirectoryPath == folder)
    }

    @Test func rejectsFileFolderAndSymlinkCollisionsWithoutChangingEitherItem() throws {
        defer { clean() }
        let source = directory.appendingPathComponent("source")
        try "source bytes".write(to: source, atomically: true, encoding: .utf8)
        let target = directory.appendingPathComponent("target")
        try "target bytes".write(to: target, atomically: true, encoding: .utf8)
        let folder = directory.appendingPathComponent("folder")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        try FileManager.default.createSymbolicLink(at: directory.appendingPathComponent("link"), withDestinationURL: directory.appendingPathComponent("missing"))
        for name in ["target", "folder", "link"] {
            #expect(throws: FileCreationError.alreadyExists(name)) { try FileRenamer.rename(source, to: name) }
        }
        #expect(try String(contentsOf: source, encoding: .utf8) == "source bytes")
        #expect(try String(contentsOf: target, encoding: .utf8) == "target bytes")
    }

    @Test func supportsCaseOnlyAndUnchangedNames() throws {
        defer { clean() }
        let source = directory.appendingPathComponent("note.txt")
        try "keep".write(to: source, atomically: true, encoding: .utf8)
        let renamed = try FileRenamer.rename(source, to: "Note.txt")
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path) == ["Note.txt"])
        _ = try FileRenamer.rename(renamed, to: "Note.txt")
        #expect(try String(contentsOf: renamed, encoding: .utf8) == "keep")
    }

    @Test func renamesSymbolicLinkInsteadOfItsTarget() throws {
        defer { clean() }
        let target = directory.appendingPathComponent("target.txt")
        let link = directory.appendingPathComponent("link.txt")
        try "target".write(to: target, atomically: true, encoding: .utf8)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
        let renamed = try FileRenamer.rename(link, to: "renamed-link.txt")
        #expect(try renamed.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink == true)
        #expect(try String(contentsOf: target, encoding: .utf8) == "target")
    }

    @Test(arguments: ["", "..", "../outside", "bad:name", "bad\nname"])
    func invalidNamesPreserveOriginal(name: String) throws {
        defer { clean() }
        let file = directory.appendingPathComponent("original")
        try "keep".write(to: file, atomically: true, encoding: .utf8)
        #expect(throws: FileCreationError.invalidName) { try FileRenamer.rename(file, to: name) }
        #expect(try String(contentsOf: file, encoding: .utf8) == "keep")
    }

    @Test func simultaneousRenamesNeverReplaceTheWinner() async throws {
        defer { clean() }
        let sources = [directory.appendingPathComponent("a"), directory.appendingPathComponent("b")]
        for file in sources { try file.lastPathComponent.write(to: file, atomically: true, encoding: .utf8) }
        let results = await withTaskGroup(of: Bool.self) { group in
            for file in sources { group.addTask { (try? FileRenamer.rename(file, to: "winner")) != nil } }
            var result: [Bool] = []
            for await value in group { result.append(value) }
            return result
        }
        #expect(results.filter { $0 }.count == 1)
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path).count == 2)
    }
}
