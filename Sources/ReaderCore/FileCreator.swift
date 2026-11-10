import Foundation
import Darwin

public enum FileCreationError: LocalizedError, Equatable {
    case invalidName
    case alreadyExists(String)
    case notDirectory

    public var errorDescription: String? {
        switch self {
        case .invalidName: coreText("请输入有效名称，不能使用 /、:、控制字符或单独的 .、..。")
        case .alreadyExists(let name): coreText("已存在名为“\(name)”的文件或文件夹，请换一个名称。")
        case .notDirectory: coreText("目标位置不是本地文件夹，请重新选择。")
        }
    }
}

public enum FileCreator {
    public static func validatedName(_ input: String) throws -> String {
        let name = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name != ".", name != "..",
              !name.contains("/"), !name.contains(":"),
              input.rangeOfCharacter(from: .controlCharacters) == nil else {
            throw FileCreationError.invalidName
        }
        return name
    }

    public static func createEmptyFile(named input: String, in folder: URL) throws -> URL {
        let file = try destination(named: input, in: folder)
        let name = file.lastPathComponent
        do {
            // Creation must fail even if another process creates the same name concurrently.
            try Data().write(to: file, options: .withoutOverwriting)
        } catch let error as CocoaError where error.code == .fileWriteFileExists {
            throw FileCreationError.alreadyExists(name)
        }
        return file
    }

    public static func createDirectory(named input: String, in folder: URL) throws -> URL {
        let directory = try destination(named: input, in: folder)
        try directory.withUnsafeFileSystemRepresentation { path in
            guard let path else { throw FileCreationError.invalidName }
            guard Darwin.mkdir(path, 0o777) == 0 else {
                let code = errno
                if code == EEXIST { throw FileCreationError.alreadyExists(directory.lastPathComponent) }
                throw NSError(domain: NSPOSIXErrorDomain, code: Int(code), userInfo: [NSFilePathErrorKey: directory.path])
            }
        }
        return directory
    }

    private static func destination(named input: String, in folder: URL) throws -> URL {
        let name = try validatedName(input)
        guard folder.isFileURL else { throw FileCreationError.notDirectory }
        let directory = folder.resolvingSymlinksInPath().standardizedFileURL
        guard try directory.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true else {
            throw FileCreationError.notDirectory
        }
        return directory.appendingPathComponent(name, isDirectory: false)
    }
}
