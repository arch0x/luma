import SwiftUI
import AppKit
import PDFKit
import ImageIO
import UniformTypeIdentifiers

struct PDFReader: View {
    @Bindable var tab: DocumentTab
    @ViewState private var document: PDFDocument?
    @ViewState private var failed = false

    var body: some View {
        Group {
            if let document { PDFCanvas(document: document, tab: tab) }
            else if failed {
                FilePlaceholder(symbol: "doc.richtext", title: "无法读取 PDF", message: "文件可能已损坏、不可访问，或超过 128 MB。", url: tab.url)
            } else { ProgressView("正在打开 PDF…") }
        }
        .task(id: tab.url) {
            let size = (try? tab.url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            if size <= 128 * 1_024 * 1_024 { document = PDFDocument(url: tab.url) }
            failed = document == nil
        }
    }
}

private struct PDFCanvas: NSViewRepresentable {
    let document: PDFDocument
    let tab: DocumentTab

    func makeCoordinator() -> Coordinator { Coordinator(tab: tab) }
    func makeNSView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.backgroundColor = LumaTheme.nativePaper
        view.document = document
        if let page = document.page(at: tab.pdfPage) { view.go(to: page) }
        context.coordinator.view = view
        NotificationCenter.default.addObserver(context.coordinator, selector: #selector(Coordinator.pageChanged), name: .PDFViewPageChanged, object: view)
        NotificationCenter.default.addObserver(context.coordinator, selector: #selector(Coordinator.selectionChanged), name: .PDFViewSelectionChanged, object: view)
        return view
    }

    func updateNSView(_ view: PDFView, context: Context) {
        let coordinator = context.coordinator
        if view.document !== document { view.document = document }
        guard coordinator.request != tab.findRequest || coordinator.query != tab.sourceQuery else { return }
        if coordinator.query != tab.sourceQuery {
            coordinator.query = tab.sourceQuery
            coordinator.matches = tab.sourceQuery.isEmpty ? [] : document.findString(tab.sourceQuery, withOptions: .caseInsensitive)
            coordinator.index = -1
            for match in coordinator.matches { match.color = LumaTheme.nativeSelection }
            view.highlightedSelections = coordinator.matches
        }
        coordinator.request = tab.findRequest
        if !coordinator.matches.isEmpty {
            coordinator.index = (coordinator.index + 1) % coordinator.matches.count
            let match = coordinator.matches[coordinator.index]
            view.setCurrentSelection(match, animate: false)
            view.go(to: match)
        }
    }

    final class Coordinator: NSObject {
        let tab: DocumentTab
        weak var view: PDFView?
        var query = ""
        var request = -1
        var matches: [PDFSelection] = []
        var index = -1
        init(tab: DocumentTab) { self.tab = tab }
        @objc func selectionChanged() {
            view?.currentSelection?.color = LumaTheme.nativeSelection
            view?.needsDisplay = true
        }
        @objc func pageChanged() {
            if let page = view?.currentPage, let document = view?.document { tab.pdfPage = document.index(for: page) }
        }
    }
}

/// Bounds image decoding independently of the original dimensions.
private actor ImageLoader {
    func thumbnail(_ url: URL) throws -> Data {
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size <= 64 * 1_024 * 1_024 else { throw ImageError.tooLarge }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: 4_096,
                kCGImageSourceCreateThumbnailWithTransform: true
              ] as CFDictionary) else { throw ImageError.unreadable }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else { throw ImageError.unreadable }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw ImageError.unreadable }
        return data as Data
    }
    enum ImageError: LocalizedError {
        case tooLarge, unreadable
        var errorDescription: String? {
            switch self {
            case .tooLarge: "图片超过 64 MB，请在默认应用中打开。"
            case .unreadable: "图片格式不受支持，或文件已经损坏。"
            }
        }
    }
}

struct ImageReader: View {
    @Bindable var tab: DocumentTab
    @ViewState private var image: NSImage?
    @ViewState private var error: String?
    private let loader = ImageLoader()

    var body: some View {
        VStack(spacing: 0) {
            if let image {
                GeometryReader { geometry in
                    let fit = tab.imageActualSize ? 1 : max(0.01, min((geometry.size.width - 64) / max(image.size.width, 1), (geometry.size.height - 64) / max(image.size.height, 1), 1))
                    ScrollView([.horizontal, .vertical]) {
                        Image(nsImage: image).resizable().interpolation(.high)
                            .frame(width: image.size.width * fit * tab.zoom, height: image.size.height * fit * tab.zoom)
                            .shadow(color: .black.opacity(0.08), radius: 12, y: 4)
                            .padding(32)
                            .frame(minWidth: geometry.size.width, minHeight: geometry.size.height)
                    }
                }.background(LumaTheme.paper)
                LumaRule()
                HStack(spacing: 6) {
                    Text("\(Int(image.size.width)) × \(Int(image.size.height)) · 最高 4096px 预览")
                        .font(.caption).foregroundStyle(LumaTheme.muted).lineLimit(1)
                    Spacer()
                    Button { tab.zoom = max(0.25, tab.zoom / 1.25) } label: { Image(systemName: "minus.magnifyingglass") }
                        .help("缩小").accessibilityLabel("缩小")
                    Button("适合窗口") { tab.imageActualSize = false; tab.zoom = 1 }
                    Button("原始大小") { tab.imageActualSize = true; tab.zoom = 1 }
                    Button { tab.zoom = min(8, tab.zoom * 1.25) } label: { Image(systemName: "plus.magnifyingglass") }
                        .help("放大").accessibilityLabel("放大")
                }.buttonStyle(LumaButtonStyle()).padding(.horizontal, 12).padding(.vertical, 4)
                    .background(LumaTheme.chrome)
            } else if let error {
                FilePlaceholder(symbol: "photo", title: "无法读取图片", message: error, url: tab.url)
            } else { ProgressView("正在打开图片…").frame(maxWidth: .infinity, maxHeight: .infinity) }
        }
        .task(id: tab.url) {
            do {
                let data = try await loader.thumbnail(tab.url)
                guard !Task.isCancelled else { return }
                image = NSImage(data: data)
                if image == nil { error = "无法解码图片。" }
            } catch { if !Task.isCancelled { self.error = error.localizedDescription } }
        }
    }
}
