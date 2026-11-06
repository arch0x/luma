import Foundation
import Darwin

public enum FileRenamer {
    public static func rename(_ source: URL, to input: String) throws -> URL {
        let name = try FileCreator.validatedName(input)
        guard source.isFileURL else { throw CocoaError(.fileReadUnsupportedScheme) }
        // Keep the final component intact: renaming a symlink must rename the link itself.
        let original = source.deletingLastPathComponent().resolvingSymlinksInPath()
            .appendingPathComponent(source.lastPathComponent)
        let values = try original.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        let isDirectory = values.isDirectory == true && values.isSymbolicLink != true
        let destination = original.deletingLastPathComponent().appendingPathComponent(name, isDirectory: isDirectory)
        return try relocate(original, to: destination)
    }

    static func relocate(_ original: URL, to destination: URL) throws -> URL {
        let name = destination.lastPathComponent
        try original.withUnsafeFileSystemRepresentation { oldPath in
            try destination.withUnsafeFileSystemRepresentation { newPath in
                guard let oldPath, let newPath else { throw FileCreationError.invalidName }
                guard renamex_np(oldPath, newPath, UInt32(RENAME_EXCL)) == 0 else {
                    let code = errno
                    if code == EEXIST { throw FileCreationError.alreadyExists(name) }
                    throw NSError(domain: NSPOSIXErrorDomain, code: Int(code), userInfo: [NSFilePathErrorKey: original.path])
                }
            }
        }
        return destination
    }
}
