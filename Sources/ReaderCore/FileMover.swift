import Foundation
import Darwin

public enum FileMoveError: LocalizedError, Equatable {
    case targetNotDirectory, sameDirectory, intoSelf
    public var errorDescription: String? {
        switch self {
        case .targetNotDirectory: "目标位置不是本地文件夹。"
        case .sameDirectory: "项目已经位于这个文件夹中。"
        case .intoSelf: "不能将文件夹移到自身或它的子文件夹中。"
        }
    }
}

public enum FileMover {
    public static func destination(for source: URL, in folder: URL) throws -> URL {
        guard source.isFileURL, folder.isFileURL else { throw FileMoveError.targetNotDirectory }
        let parent = source.deletingLastPathComponent().resolvingSymlinksInPath().standardizedFileURL
        let original = parent.appendingPathComponent(source.lastPathComponent)
        let values = try original.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        let isDirectory = values.isDirectory == true && values.isSymbolicLink != true
        let target = folder.resolvingSymlinksInPath().standardizedFileURL
        guard try target.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true else { throw FileMoveError.targetNotDirectory }
        guard target.path != parent.path else { throw FileMoveError.sameDirectory }
        if isDirectory {
            let path = original.path
            guard target.path != path, !target.path.hasPrefix(path == "/" ? "/" : path + "/") else { throw FileMoveError.intoSelf }
        }
        return target.appendingPathComponent(original.lastPathComponent, isDirectory: isDirectory)
    }

    public static func move(_ source: URL, into folder: URL) throws -> URL {
        let destination = try destination(for: source, in: folder)
        let original = source.deletingLastPathComponent().resolvingSymlinksInPath().appendingPathComponent(source.lastPathComponent)
        do { return try FileRenamer.relocate(original, to: destination) }
        catch let error as NSError where error.domain == NSPOSIXErrorDomain && error.code == Int(EXDEV) {
            // Foundation performs a cross-volume move; an existing target is never replaced.
            do { try FileManager.default.moveItem(at: original, to: destination) }
            catch let error as CocoaError where error.code == .fileWriteFileExists { throw FileCreationError.alreadyExists(destination.lastPathComponent) }
            return destination
        }
    }
}
