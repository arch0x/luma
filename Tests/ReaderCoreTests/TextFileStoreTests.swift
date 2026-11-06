import Foundation
import Testing
@testable import ReaderCore

struct TextFileStoreTests {
    let directory: URL
    init() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }
    private func clean() { try? FileManager.default.removeItem(at: directory) }

    @Test(arguments: ["\n", "\r\n", "\r"])
    func savesPreserveBOMNewlineAndPermissions(newline: String) throws {
        defer { clean() }
        let file = directory.appendingPathComponent("note.csv")
        try Data(("\u{FEFF}name,count" + newline + "初稿,1" + newline).utf8).write(to: file)
        try FileManager.default.setAttributes([.posixPermissions: 0o640], ofItemAtPath: file.path)
        let snapshot = try TextFileStore.read(at: file)
        #expect(snapshot.text == "name,count\n初稿,1\n")
        let saved = try TextFileStore.save("name,count\n修改,2\n", at: file, format: snapshot, expected: snapshot.version)
        #expect(try Data(contentsOf: file) == Data(("\u{FEFF}name,count" + newline + "修改,2" + newline).utf8))
        #expect(saved.version == (try TextFileStore.version(at: file)))
        #expect((try FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as? NSNumber)?.intValue == 0o640)
    }

    @Test func changedBytesAreDetectedEvenIfTimestampAndLengthStayTheSame() throws {
        defer { clean() }
        let file = directory.appendingPathComponent("note.txt")
        try Data("original".utf8).write(to: file)
        let snapshot = try TextFileStore.read(at: file)
        let date = try #require(try FileManager.default.attributesOfItem(atPath: file.path)[.modificationDate])
        try Data("external".utf8).write(to: file, options: .atomic)
        try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: file.path)
        do {
            _ = try TextFileStore.save("my draft", at: file, format: snapshot, expected: snapshot.version)
            Issue.record("External edit was overwritten")
        } catch TextFileWriteError.changed(let version) {
            #expect(version != snapshot.version)
            #expect(try String(contentsOf: file, encoding: .utf8) == "external")
        }
    }

    @Test func deletedFilesNeedExplicitMissingVersionBeforeRecreation() throws {
        defer { clean() }
        let file = directory.appendingPathComponent("note.txt")
        try Data("original".utf8).write(to: file)
        let snapshot = try TextFileStore.read(at: file)
        try FileManager.default.removeItem(at: file)
        #expect(try TextFileStore.version(at: file) == .missing)
        do {
            _ = try TextFileStore.save("draft", at: file, format: snapshot, expected: snapshot.version)
            Issue.record("Missing file was silently recreated")
        } catch TextFileWriteError.changed(let version) { #expect(version == .missing) }
        _ = try TextFileStore.save("draft", at: file, format: snapshot, expected: .missing)
        #expect(try String(contentsOf: file, encoding: .utf8) == "draft")
    }

    @Test func rejectedWritesKeepOriginalBytes() throws {
        defer { clean() }
        let file = directory.appendingPathComponent("note.txt")
        let original = Data("original".utf8)
        try original.write(to: file)
        let snapshot = try TextFileStore.read(at: file)
        #expect(throws: (any Error).self) { try TextFileStore.save("bad\0text", at: file, format: snapshot, expected: snapshot.version) }
        #expect(throws: (any Error).self) { try TextFileStore.save(String(repeating: "x", count: FileReader.textLimit + 1), at: file, format: snapshot, expected: snapshot.version) }
        #expect(try Data(contentsOf: file) == original)
    }

    @Test func readOnlyFilesAreNotReplacedEvenIfParentDirectoryIsWritable() throws {
        defer { clean() }
        let file = directory.appendingPathComponent("readonly.txt")
        try Data("original".utf8).write(to: file)
        let snapshot = try TextFileStore.read(at: file)
        try FileManager.default.setAttributes([.posixPermissions: 0o444], ofItemAtPath: file.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: file.path) }
        #expect(throws: (any Error).self) { try TextFileStore.save("draft", at: file, format: snapshot, expected: snapshot.version) }
        #expect(try String(contentsOf: file, encoding: .utf8) == "original")
    }
}
