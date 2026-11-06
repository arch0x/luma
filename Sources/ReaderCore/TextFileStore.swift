import Foundation
import CryptoKit

public enum DiskVersion: Equatable, Sendable {
    case missing
    case content(Data)
}

public struct TextFileSnapshot: Sendable {
    public let text: String
    public let version: DiskVersion
    public let hasBOM: Bool
    public let newline: String

    public init(data: Data) throws {
        guard data.count <= FileReader.textLimit else { throw ReaderError.tooLarge(FileReader.textLimit) }
        guard !data.contains(0) else { throw ReaderError.binary }
        guard var source = String(data: data, encoding: .utf8) else { throw ReaderError.notUTF8 }
        hasBOM = data.starts(with: [0xef, 0xbb, 0xbf])
        if source.hasPrefix("\u{FEFF}") { source.removeFirst() }
        if let first = source.firstIndex(where: { $0 == "\n" || $0 == "\r" || $0 == "\r\n" }) {
            newline = String(source[first])
        } else { newline = "\n" }
        text = Self.normalize(source)
        version = .content(Data(SHA256.hash(data: data)))
    }

    public func encode(_ text: String) throws -> Data {
        let source = Self.normalize(text).replacingOccurrences(of: "\n", with: newline)
        let data = Data(((hasBOM ? "\u{FEFF}" : "") + source).utf8)
        guard data.count <= FileReader.textLimit else { throw ReaderError.tooLarge(FileReader.textLimit) }
        guard !data.contains(0) else { throw ReaderError.binary }
        return data
    }

    private static func normalize(_ text: String) -> String {
        text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
    }
}

public enum TextFileWriteError: Error, Sendable {
    case changed(DiskVersion)
    case coordinationFailed
}

public enum TextFileStore {
    private static func bytes(at url: URL) throws -> Data {
        let file = try FileHandle(forReadingFrom: url)
        defer { try? file.close() }
        let data = try file.read(upToCount: FileReader.textLimit + 1) ?? Data()
        guard data.count <= FileReader.textLimit else { throw ReaderError.tooLarge(FileReader.textLimit) }
        return data
    }

    public static func read(at url: URL) throws -> TextFileSnapshot {
        try TextFileSnapshot(data: bytes(at: url))
    }

    public static func version(at url: URL) throws -> DiskVersion {
        do { return .content(Data(SHA256.hash(data: try bytes(at: url)))) }
        catch let error as CocoaError where error.code == .fileReadNoSuchFile || error.code == .fileNoSuchFile {
            return .missing
        }
    }

    /// Compare inside the coordinated write, including after a conflict dialog.
    /// The atomic replacement keeps a failed write from leaving a partial file.
    public static func save(_ text: String, at url: URL, format: TextFileSnapshot, expected: DiskVersion) throws -> TextFileSnapshot {
        let data = try format.encode(text)
        var coordinationError: NSError?
        var result: Result<TextFileSnapshot, any Error>?
        NSFileCoordinator().coordinate(writingItemAt: url, options: .forReplacing, error: &coordinationError) { target in
            result = Result {
                let current = try version(at: target)
                guard current == expected else { throw TextFileWriteError.changed(current) }
                if current != .missing && !FileManager.default.isWritableFile(atPath: target.path) {
                    throw CocoaError(.fileWriteNoPermission)
                }
                try data.write(to: target, options: .atomic)
                return try TextFileSnapshot(data: data)
            }
        }
        if let coordinationError { throw coordinationError }
        guard let result else { throw TextFileWriteError.coordinationFailed }
        return try result.get()
    }
}
