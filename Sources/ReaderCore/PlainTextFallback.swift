import Foundation
import UniformTypeIdentifiers

/// Unknown extensions may contain text, but registered binary formats must keep their own handlers.
public enum PlainTextFallback {
    private static let binaryExtensions: Set<String> = [
        "zip", "gz", "bz2", "xz", "7z", "rar", "tar", "zst", "dmg", "iso", "pkg",
        "doc", "docx", "xls", "xlsx", "ppt", "pptx", "pages", "numbers", "key", "epub",
        "rtf", "rtfd", "ttf", "otf", "woff", "woff2", "sqlite", "sqlite3", "db", "bin",
        "png", "jpg", "jpeg", "gif", "heic", "heif", "tiff", "tif", "bmp", "webp", "icns", "ico", "pdf",
        "mp3", "m4a", "wav", "flac", "aac", "ogg", "mp4", "mov", "mkv", "avi", "webm",
        "exe", "dll", "dylib", "so", "a", "o", "class", "jar", "wasm", "psd", "sketch"
    ]

    public static func permits(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        // Keep common binaries excluded even when Launch Services has no registered type (e.g. in a test runner).
        guard !binaryExtensions.contains(ext) else { return false }
        guard !ext.isEmpty else { return true }
        guard let type = UTType(filenameExtension: ext), type.isDeclared else { return true }
        if type.conforms(to: .text) || type.conforms(to: .sourceCode) { return true }
        let binaryTypes: [UTType] = [.image, .audiovisualContent, .archive, .font, .executable, .spreadsheet, .presentation, .database]
        // Generic data and formats such as Wavefront OBJ or .strings still need content detection.
        return !binaryTypes.contains { type.conforms(to: $0) }
    }

    public static func validate(_ data: Data) throws {
        // Several binary containers have ASCII headers and can even be valid UTF-8 when empty.
        let signatures: [[UInt8]] = [
            Array("%PDF-".utf8), Array("bplist00".utf8), Array("{\\rtf".utf8),
            [0x50, 0x4b, 0x03, 0x04], [0x50, 0x4b, 0x05, 0x06], [0x50, 0x4b, 0x07, 0x08],
            Array("GIF87a".utf8), Array("GIF89a".utf8), Array("RIFF".utf8), Array("OTTO".utf8)
        ]
        guard !signatures.contains(where: { data.starts(with: $0) }),
              !data.contains(where: { ($0 < 0x20 && ![0x09, 0x0a, 0x0c, 0x0d].contains($0)) || $0 == 0x7f }) else {
            throw ReaderError.binary
        }
    }
}
