import Foundation
import ImageIO
import UniformTypeIdentifiers
import WebKit
import ReaderCore

enum MarkdownImageError: LocalizedError {
    case outsideWorkspace, unsupported, tooLarge, budget
    var errorDescription: String? {
        switch self {
        case .outsideWorkspace: readerText("图片不在当前工作区内。请添加包含该图片的文件夹。")
        case .unsupported: readerText("图片不存在、格式不受支持或文件已损坏。")
        case .tooLarge: readerText("图片超过预览大小限制。")
        case .budget: readerText("此文档的图片预览已达到大小限制。")
        }
    }
}

/// Document-scoped access; symlinks and encoded paths are checked after resolution.
nonisolated enum MarkdownImageLocation {
    static func resolve(_ source: String, document: URL, root: URL) throws -> URL {
        guard source.utf8.count <= 16_384, !source.hasPrefix("//"), !source.contains("\u{0}"),
              let url = URL(string: encodedReference(source), relativeTo: document)?.absoluteURL,
              url.isFileURL, url.host == nil || url.host == "" || url.host == "localhost" else {
            throw MarkdownImageError.outsideWorkspace
        }
        let resolved = url.resolvingSymlinksInPath().standardizedFileURL
        let root = root.resolvingSymlinksInPath().standardizedFileURL
        let prefix = root.path == "/" ? "/" : root.path + "/"
        guard !resolved.path.contains("\u{0}"), resolved.path.hasPrefix(prefix) else { throw MarkdownImageError.outsideWorkspace }
        return resolved
    }

    /// Foundation double-encodes existing %20 when the same input also has Unicode.
    /// Encode UTF-8 bytes while preserving only already-valid percent triplets.
    private static func encodedReference(_ source: String) -> String {
        let bytes = Array(source.utf8)
        let safe = Set("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~:/?#[]@!$&'()*+,;=".utf8)
        let hex = Array("0123456789ABCDEF".utf8)
        func isHex(_ value: UInt8) -> Bool { (48...57).contains(value) || (65...70).contains(value) || (97...102).contains(value) }
        var output: [UInt8] = []
        var index = 0
        while index < bytes.count {
            let byte = bytes[index]
            if byte == 37, index + 2 < bytes.count, isHex(bytes[index + 1]), isHex(bytes[index + 2]) {
                output.append(contentsOf: bytes[index...index + 2]); index += 3
            } else if safe.contains(byte) {
                output.append(byte); index += 1
            } else {
                output.append(contentsOf: [37, hex[Int(byte >> 4)], hex[Int(byte & 15)]]); index += 1
            }
        }
        return String(decoding: output, as: UTF8.self)
    }
}

struct MarkdownImagePayload: Sendable {
    let data: Data
    let mime: String
}

/// Disk reads and ImageIO preparation run on this actor, never during UI layout.
actor MarkdownImageLoader {
    let document: URL
    let root: URL
    private var cache: [URL: MarkdownImagePayload] = [:]
    private var cachedBytes = 0
    static let fileLimit = 64 * 1_024 * 1_024
    static let cacheLimit = 64 * 1_024 * 1_024

    init(document: URL, root: URL) { self.document = document; self.root = root }

    func image(_ source: String) throws -> MarkdownImagePayload {
        try Task.checkCancellation()
        let url = try MarkdownImageLocation.resolve(source, document: document, root: root)
        if let cached = cache[url] { return cached }
        guard cache.count < 100, cachedBytes < Self.cacheLimit else { throw MarkdownImageError.budget }
        let values = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
        guard values.isRegularFile == true else { throw MarkdownImageError.unsupported }
        let svg = url.pathExtension.lowercased() == "svg"
        let limit = svg ? 1_024 * 1_024 : Self.fileLimit
        guard (values.fileSize ?? 0) <= limit else { throw MarkdownImageError.tooLarge }
        let file = try FileHandle(forReadingFrom: url)
        defer { try? file.close() }
        let data = try file.read(upToCount: limit + 1) ?? Data()
        guard data.count <= limit else { throw MarkdownImageError.tooLarge }
        try Task.checkCancellation()

        let payload: MarkdownImagePayload
        if svg {
            guard let text = String(data: data, encoding: .utf8) else { throw MarkdownImageError.unsupported }
            try SVGDocument.validate(text)
            // SVG is served only as an image, with a separate deny-all resource policy.
            payload = MarkdownImagePayload(data: data, mime: "image/svg+xml")
        } else {
            guard let source = CGImageSourceCreateWithData(data as CFData, nil),
                  let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceThumbnailMaxPixelSize: 2_048,
                    kCGImageSourceCreateThumbnailWithTransform: true
                  ] as CFDictionary) else { throw MarkdownImageError.unsupported }
            let output = NSMutableData()
            guard let destination = CGImageDestinationCreateWithData(output, UTType.png.identifier as CFString, 1, nil) else { throw MarkdownImageError.unsupported }
            CGImageDestinationAddImage(destination, image, nil)
            guard CGImageDestinationFinalize(destination) else { throw MarkdownImageError.unsupported }
            payload = MarkdownImagePayload(data: output as Data, mime: "image/png")
        }
        guard cachedBytes + payload.data.count <= Self.cacheLimit else { throw MarkdownImageError.budget }
        try Task.checkCancellation()
        cache[url] = payload
        cachedBytes += payload.data.count
        return payload
    }
}

final class MarkdownImageSchemeHandler: NSObject, WKURLSchemeHandler {
    private let loader: MarkdownImageLoader
    private var tasks: [ObjectIdentifier: Task<Void, Never>] = [:]
    init(document: URL, root: URL) { loader = MarkdownImageLoader(document: document, root: root) }

    func webView(_ webView: WKWebView, start urlSchemeTask: any WKURLSchemeTask) {
        let id = ObjectIdentifier(urlSchemeTask)
        guard let url = urlSchemeTask.request.url, url.scheme == "luma-image", url.host == "document",
              let source = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "src" })?.value else {
            urlSchemeTask.didFailWithError(URLError(.badURL)); return
        }
        tasks[id] = Task { [weak self] in
            guard let self else { return }
            defer { tasks[id] = nil }
            do {
                let payload = try await loader.image(source)
                guard !Task.isCancelled, tasks[id] != nil else { return }
                let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: [
                    "Content-Type": payload.mime,
                    "Content-Security-Policy": "default-src 'none'; style-src 'unsafe-inline'; sandbox"
                ]) ?? URLResponse(url: url, mimeType: payload.mime, expectedContentLength: payload.data.count, textEncodingName: nil)
                urlSchemeTask.didReceive(response)
                urlSchemeTask.didReceive(payload.data)
                urlSchemeTask.didFinish()
            } catch {
                guard !Task.isCancelled, tasks[id] != nil else { return }
                urlSchemeTask.didFailWithError(error)
            }
        }
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: any WKURLSchemeTask) {
        tasks.removeValue(forKey: ObjectIdentifier(urlSchemeTask))?.cancel()
    }
}
