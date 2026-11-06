import Foundation
import Testing
@testable import ReaderCore

struct FileMoveTests {
    let directory: URL
    let source: URL
    let target: URL
    init() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        source = directory.appendingPathComponent("Source", isDirectory: true)
        target = directory.appendingPathComponent("Target", isDirectory: true)
        for folder in [source, target] { try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true) }
    }
    private func clean() { try? FileManager.default.removeItem(at: directory) }

    @Test(arguments: [false, true])
    func movesFilesAndFoldersWithoutChangingContents(folder: Bool) throws {
        defer { clean() }
        let item = source.appendingPathComponent("中文 100%")
        if folder { try FileManager.default.createDirectory(at: item, withIntermediateDirectories: false) }
        let file = folder ? item.appendingPathComponent("inside.txt") : item
        try "keep all bytes".write(to: file, atomically: true, encoding: .utf8)
        let inode = try FileManager.default.attributesOfItem(atPath: file.path)[.systemFileNumber] as? NSNumber
        let moved = try FileMover.move(item, into: target)
        let movedFile = folder ? moved.appendingPathComponent("inside.txt") : moved
        #expect(!FileManager.default.fileExists(atPath: item.path))
        #expect(try String(contentsOf: movedFile, encoding: .utf8) == "keep all bytes")
        #expect(try FileManager.default.attributesOfItem(atPath: movedFile.path)[.systemFileNumber] as? NSNumber == inode)
    }

    @Test func rejectsOriginalParentSelfDescendantAndSymlinkIntoDescendant() throws {
        defer { clean() }
        let item = source.appendingPathComponent("Folder", isDirectory: true)
        let child = item.appendingPathComponent("Child", isDirectory: true)
        try FileManager.default.createDirectory(at: child, withIntermediateDirectories: true)
        #expect(throws: FileMoveError.sameDirectory) { try FileMover.move(item, into: source) }
        for folder in [item, child] { #expect(throws: FileMoveError.intoSelf) { try FileMover.move(item, into: folder) } }
        let alias = target.appendingPathComponent("alias")
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: child)
        #expect(throws: FileMoveError.intoSelf) { try FileMover.move(item, into: alias) }
        #expect(FileManager.default.fileExists(atPath: child.path))
    }

    @Test(arguments: [false, true])
    func collisionsNeverOverwriteFilesOrFolders(folder: Bool) throws {
        defer { clean() }
        let item = source.appendingPathComponent("same")
        let existing = target.appendingPathComponent("same")
        if folder { try FileManager.default.createDirectory(at: item, withIntermediateDirectories: false) }
        else { try "original".write(to: item, atomically: true, encoding: .utf8) }
        try "existing".write(to: existing, atomically: true, encoding: .utf8)
        #expect(throws: FileCreationError.alreadyExists("same")) { try FileMover.move(item, into: target) }
        #expect(FileManager.default.fileExists(atPath: item.path))
        #expect(try String(contentsOf: existing, encoding: .utf8) == "existing")
    }

    @Test func movingSymlinkLeavesTargetIntact() throws {
        defer { clean() }
        let file = source.appendingPathComponent("original.txt")
        let link = source.appendingPathComponent("link.txt")
        try "original".write(to: file, atomically: true, encoding: .utf8)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: file)
        let moved = try FileMover.move(link, into: target)
        #expect(try moved.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink == true)
        #expect(try String(contentsOf: file, encoding: .utf8) == "original")
    }

    @Test func invalidOrUnwritableTargetKeepsSource() throws {
        defer { clean() }
        let file = source.appendingPathComponent("note.txt")
        try "original".write(to: file, atomically: true, encoding: .utf8)
        #expect(throws: FileMoveError.targetNotDirectory) { try FileMover.move(file, into: file) }
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: target.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: target.path) }
        #expect(throws: (any Error).self) { try FileMover.move(file, into: target) }
        #expect(try String(contentsOf: file, encoding: .utf8) == "original")
    }

    @Test func concurrentMovesWithSameNameHaveOneWinner() async throws {
        defer { clean() }
        let other = directory.appendingPathComponent("Other", isDirectory: true)
        try FileManager.default.createDirectory(at: other, withIntermediateDirectories: false)
        let files = [source.appendingPathComponent("same.txt"), other.appendingPathComponent("same.txt")]
        for (index, file) in files.enumerated() { try "source \(index)".write(to: file, atomically: true, encoding: .utf8) }
        let target = target
        let successes = await withTaskGroup(of: Int.self) { group in
            for file in files { group.addTask { (try? FileMover.move(file, into: target)) == nil ? 0 : 1 } }
            var count = 0
            for await value in group { count += value }
            return count
        }
        #expect(successes == 1)
        #expect(files.filter { FileManager.default.fileExists(atPath: $0.path) }.count == 1)
    }
}
