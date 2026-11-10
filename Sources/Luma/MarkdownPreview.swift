import SwiftUI
import AppKit
import WebKit
import Observation

@Observable final class MarkdownRenderState {
    var loading = true
    var error: String?
    var metrics: [String: Int] = [:]
    var headings: [MarkdownHeading] = []
    var activeHeadingID: String?
    var outlineTruncated = false
    var navigationTarget = ""
    var navigationRequest = 0
    var navigationLocation: MarkdownReadingLocation?
    var addingBookmark = false

    func navigate(to id: String = "") {
        navigationTarget = id
        navigationLocation = nil
        navigationRequest += 1
    }

    func navigate(to location: MarkdownReadingLocation) {
        navigationLocation = location
        navigationTarget = ""
        navigationRequest += 1
    }
}

struct MarkdownPreview: View {
    let source: String
    let tab: DocumentTab
    let imageRoot: URL
    let previewWidth: Double
    let typography: MarkdownTypography
    let state: MarkdownRenderState
    let workspace: Workspace
    @Binding var showingInformation: Bool
    let onOpen: ([URL]) -> Void
    @Environment(\.colorScheme) private var colorScheme
    @ViewState private var sectionPeek = MarkdownSectionPeek()
    @ViewState private var showOutlineList = false

    var body: some View {
        HStack(spacing: 0) {
            DocumentReaderRail(tab: tab, workspace: workspace, showingInformation: $showingInformation,
                               navigationHeight: MarkdownSectionRail.contentHeight(for: state)) {
                if state.error == nil {
                    MarkdownSectionRail(state: state, peek: sectionPeek)
                    .contextMenu {
                        if !state.headings.isEmpty {
                            Button("打开层级目录") {
                                sectionPeek.dismiss()
                                showOutlineList = true
                            }
                        }
                    }
                    .popover(isPresented: $showOutlineList, arrowEdge: .trailing) {
                        MarkdownOutlineView(state: state, tab: tab) { showOutlineList = false }
                            .frame(width: 274, height: 370)
                    }
                } else { Spacer(minLength: 0) }
            }
            reader
        }
        .markdownSectionPreview(tab: tab, state: state, peek: sectionPeek, suppressed: showingInformation)
        .onChange(of: state.headings.map(\.id)) { _, _ in sectionPeek.dismiss() }
    }

    private var reader: some View {
        ZStack {
            MarkdownWebView(source: source, tab: tab, imageRoot: imageRoot, previewWidth: previewWidth, typography: typography, dark: colorScheme == .dark, state: state, navigationRequest: state.navigationRequest, findRequest: tab.markdownFind.request, bookmarkRequest: tab.markdownBookmarkRequest, onOpen: onOpen)
                .id(imageRoot)
                .opacity(state.error == nil && (!state.loading || !state.metrics.isEmpty) ? 1 : 0)
            if state.loading { ProgressView("正在排版…").padding().background(LumaTheme.chrome, in: RoundedRectangle(cornerRadius: 8)) }
            if let error = state.error {
                VStack(spacing: 16) {
                    Image(systemName: "text.document").font(.largeTitle).foregroundStyle(.secondary)
                    Text("Markdown 预览暂时不可用").font(.headline)
                    Text(error).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 420)
                    Button("查看源码") { tab.showSource = true }
                        .buttonStyle(LumaButtonStyle(emphasis: .secondary))
                }.padding(30)
            }
        }
    }
}

/// Only bundled engines/fonts are exposed on this scheme. Images use a separate handler.
enum MarkdownResources {
    static let entryURL = URL(string: "luma-preview://reader/index.html")!
    static let allowedFiles: Set<String> = [
        "index.html", "preview.css", "preview.js", "content-tools.js", "search.js", "reading.js", "json.js", "languages.js", "vendor/marked.umd.js", "vendor/purify.min.js",
        "vendor/highlight.min.js", "vendor/swift.min.js", "vendor/rust.min.js", "vendor/typescript.min.js", "vendor/mermaid.min.js",
        "vendor/katex/katex.min.js", "vendor/katex/katex.min.css"
    ]

    static func resource(for url: URL) throws -> (Data, String) {
        let path = String(url.path.dropFirst())
        let isFont = path.range(of: #"^vendor/katex/fonts/KaTeX_[A-Za-z0-9-]+\.(woff2?|ttf)$"#, options: .regularExpression) != nil
        guard url.scheme == "luma-preview", url.host == "reader", allowedFiles.contains(path) || isFont,
              let folder = Bundle.module.url(forResource: "Markdown", withExtension: nil) else {
            throw URLError(.fileDoesNotExist)
        }
        let mime: String = switch url.pathExtension {
        case "html": "text/html"
        case "css": "text/css"
        case "woff2": "font/woff2"
        case "woff": "font/woff"
        case "ttf": "font/ttf"
        default: "text/javascript"
        }
        return (try Data(contentsOf: folder.appendingPathComponent(path)), mime)
    }
}

final class MarkdownSchemeHandler: NSObject, WKURLSchemeHandler {
    func webView(_ webView: WKWebView, start urlSchemeTask: any WKURLSchemeTask) {
        do {
            guard let url = urlSchemeTask.request.url else { throw URLError(.badURL) }
            let (data, mime) = try MarkdownResources.resource(for: url)
            urlSchemeTask.didReceive(URLResponse(url: url, mimeType: mime, expectedContentLength: data.count, textEncodingName: "utf-8"))
            urlSchemeTask.didReceive(data)
            urlSchemeTask.didFinish()
        } catch { urlSchemeTask.didFailWithError(error) }
    }
    func webView(_ webView: WKWebView, stop urlSchemeTask: any WKURLSchemeTask) { }
}

struct MarkdownWebView: NSViewRepresentable {
    let source: String
    let tab: DocumentTab
    let imageRoot: URL
    let previewWidth: Double
    let typography: MarkdownTypography
    let dark: Bool
    let state: MarkdownRenderState
    // Makes a native outline action update this view even when source/theme stay unchanged.
    let navigationRequest: Int
    let findRequest: Int
    let bookmarkRequest: Int
    let onOpen: ([URL]) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(source: source, tab: tab, imageRoot: imageRoot, previewWidth: previewWidth, typography: typography, dark: dark, state: state, onOpen: onOpen)
    }

    static func makeWebView(coordinator: Coordinator) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.setURLSchemeHandler(MarkdownSchemeHandler(), forURLScheme: "luma-preview")
        configuration.setURLSchemeHandler(MarkdownImageSchemeHandler(document: coordinator.tab.url, root: coordinator.imageRoot), forURLScheme: "luma-image")
        configuration.userContentController.add(coordinator, name: "luma")
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = coordinator
        webView.allowsBackForwardNavigationGestures = false
        coordinator.webView = webView
        coordinator.tab.markdownCaptureID = coordinator.captureID
        coordinator.tab.captureMarkdownPosition = { [weak coordinator] in await coordinator?.finishReadingSession() }
        webView.load(URLRequest(url: MarkdownResources.entryURL))
        return webView
    }

    func makeNSView(context: Context) -> WKWebView { Self.makeWebView(coordinator: context.coordinator) }

    func updateNSView(_ webView: WKWebView, context: Context) {
        let coordinator = context.coordinator
        coordinator.source = source
        coordinator.dark = dark
        coordinator.previewWidth = previewWidth
        coordinator.typography = typography
        coordinator.renderIfNeeded()
        coordinator.layoutIfNeeded()
        coordinator.navigateIfNeeded()
        coordinator.findIfNeeded()
        coordinator.bookmarkIfNeeded()
    }

    static func dismantleNSView(_ webView: WKWebView, coordinator: Coordinator) {
        coordinator.renderTask?.cancel()
        coordinator.navigationTask?.cancel()
        coordinator.findTask?.cancel()
        coordinator.layoutTask?.cancel()
        Task {
            await coordinator.finishReadingSession()
            if coordinator.tab.markdownCaptureID == coordinator.captureID {
                coordinator.tab.captureMarkdownPosition = nil
                coordinator.tab.markdownCaptureID = nil
            }
            webView.stopLoading()
            webView.configuration.userContentController.removeScriptMessageHandler(forName: "luma")
            webView.navigationDelegate = nil
        }
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var source: String
        var dark: Bool
        var previewWidth: Double
        var typography: MarkdownTypography
        let tab: DocumentTab
        let imageRoot: URL
        let state: MarkdownRenderState
        let onOpen: ([URL]) -> Void
        weak var webView: WKWebView?
        var loaded = false
        var renderTask: Task<Void, Never>?
        var navigationTask: Task<Void, Never>?
        var findTask: Task<Void, Never>?
        var layoutTask: Task<Void, Never>?
        var bookmarkTask: Task<Void, Never>?
        let captureID = UUID()
        private var rendering = false
        private var lastNavigationRequest: Int
        private var lastSource: String?
        private var lastDark: Bool?
        private var lastCodeLanguage: CodeLanguage?
        private var revision = 0
        private var findRevision = 0
        private var lastFindRequest: Int?
        private var lastFindQuery: String?
        private var lastWidth: Double?
        private var lastTypography: MarkdownTypography?
        private var layoutRevision = 0
        private var bookmarkInFlightRequest: Int?

        init(source: String, tab: DocumentTab, imageRoot: URL? = nil, previewWidth: Double = 0, typography: MarkdownTypography = .init(), dark: Bool, state: MarkdownRenderState, onOpen: @escaping ([URL]) -> Void) {
            self.source = source; self.tab = tab; self.dark = dark; self.state = state; self.onOpen = onOpen
            self.imageRoot = imageRoot ?? tab.url.deletingLastPathComponent()
            self.previewWidth = previewWidth
            self.typography = typography
            lastNavigationRequest = state.navigationRequest
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            loaded = true
            renderIfNeeded()
        }

        func renderIfNeeded() {
            let codeLanguage = tab.codeLanguage
            guard loaded, let webView, lastSource != source || lastDark != dark || lastCodeLanguage != codeLanguage else { return }
            lastSource = source; lastDark = dark; lastCodeLanguage = codeLanguage
            rendering = true
            renderTask?.cancel()
            findTask?.cancel()
            layoutTask?.cancel()
            findRevision += 1
            revision += 1
            let current = revision
            let source = source
            let dark = dark
            let offset = tab.markdownOffset
            let location = tab.markdownLocation?.javascriptValue
            let width = previewWidth
            let typography = typography
            lastWidth = width
            lastTypography = typography
            renderTask = Task { [weak self, weak webView] in
                guard let self, let webView else { return }
                state.loading = true; state.error = nil
                do {
                    let result = try await webView.callAsyncJavaScript(
                        "try { return await window.luma.render(source, options); } catch (error) { return {renderError: String(error.message || error).slice(0, 600)}; }",
                        arguments: ["source": source, "options": ["dark": dark, "offset": offset, "width": width, "typography": typography.javascriptValue, "location": location ?? [:], "codeLanguage": codeLanguage?.identifier ?? "", "codeTitle": codeLanguage?.title ?? ""]],
                        in: nil, contentWorld: .page
                    )
                    guard !Task.isCancelled, current == revision else { return }
                    if let values = result as? [String: Any] {
                        if let message = values["renderError"] as? String {
                            state.loading = false; state.error = message; rendering = false
                            return
                        }
                        state.metrics = values.compactMapValues { ($0 as? NSNumber)?.intValue }
                    }
                    state.loading = false
                    rendering = false
                    layoutIfNeeded()
                    navigateIfNeeded()
                    findIfNeeded(force: true)
                    bookmarkIfNeeded()
                } catch {
                    guard !Task.isCancelled, current == revision else { return }
                    state.loading = false; state.error = error.localizedDescription
                    rendering = false
                }
            }
        }

        func navigateIfNeeded() {
            guard loaded, !rendering, state.error == nil, lastNavigationRequest != state.navigationRequest, let webView else { return }
            lastNavigationRequest = state.navigationRequest
            let target = state.navigationTarget
            let location = state.navigationLocation?.javascriptValue
            navigationTask?.cancel()
            navigationTask = Task { [weak webView] in
                guard let webView else { return }
                do {
                    let result = try await webView.callAsyncJavaScript("return location ? window.luma.restoreReadingPosition(location) : window.luma.navigateToHeading(target);", arguments: ["target": target, "location": location.map { $0 as Any } ?? NSNull()], in: nil, contentWorld: .page)
                    guard !Task.isCancelled, result as? Bool == true else { return }
                    webView.window?.makeFirstResponder(webView)
                } catch { /* A refresh can replace the page while a navigation is pending. */ }
            }
        }

        func capturePosition() async {
            guard loaded, !rendering, tab.markdownCaptureID == captureID, let webView else { return }
            do {
                let result = try await webView.callAsyncJavaScript("return window.luma.getReadingPosition();", arguments: [:], in: nil, contentWorld: .page)
                guard tab.markdownCaptureID == captureID, let values = result as? [String: Any], let position = MarkdownReadingLocation(message: values) else { return }
                tab.rememberReadingPosition(position)
            } catch { }
        }

        func finishReadingSession() async {
            bookmarkIfNeeded()
            await bookmarkTask?.value
            await capturePosition()
        }

        func layoutIfNeeded() {
            guard loaded, !rendering, lastWidth != previewWidth || lastTypography != typography, let webView else { return }
            let width = previewWidth
            let typography = typography
            lastWidth = width
            lastTypography = typography
            layoutTask?.cancel(); layoutRevision += 1
            let current = layoutRevision
            layoutTask = Task { [weak self, weak webView] in
                guard let self, let webView else { return }
                do {
                    // Apply while dragging; obsolete updates can cancel before reaching WebKit.
                    try Task.checkCancellation()
                    let result = try await webView.callAsyncJavaScript("return window.luma.setReadingLayout(options);", arguments: ["options": ["width": width, "typography": typography.javascriptValue]], in: nil, contentWorld: .page)
                    guard !Task.isCancelled, current == layoutRevision, let values = result as? [String: Any], let position = MarkdownReadingLocation(message: values) else { return }
                    tab.rememberReadingPosition(position)
                } catch { }
            }
        }

        func bookmarkIfNeeded() {
            guard loaded, !rendering, tab.markdownBookmarkRequest != tab.markdownBookmarkHandledRequest,
                  let session = tab.readingSession, let webView else { return }
            let request = tab.markdownBookmarkRequest
            let headingID = tab.markdownBookmarkHeadingID
            guard bookmarkInFlightRequest != request else { return }
            bookmarkTask?.cancel()
            bookmarkInFlightRequest = request
            state.addingBookmark = true
            bookmarkTask = Task { [weak self, weak webView] in
                guard let self, let webView else { return }
                defer {
                    if bookmarkInFlightRequest == request {
                        bookmarkInFlightRequest = nil
                        state.addingBookmark = false
                    }
                }
                do {
                    let result = try await webView.callAsyncJavaScript(
                        "return headingID ? window.luma.getHeadingReadingPosition(headingID) : window.luma.getReadingPosition();",
                        arguments: ["headingID": headingID as Any? ?? NSNull()], in: nil, contentWorld: .page)
                    guard !Task.isCancelled, tab.markdownCaptureID == captureID, tab.markdownBookmarkRequest == request else { return }
                    tab.markdownBookmarkHandledRequest = request
                    guard let values = result as? [String: Any], let position = MarkdownReadingLocation(message: values) else { return }
                    if headingID == nil { tab.rememberReadingPosition(position) }
                    session.addBookmark(at: position, title: values["title"] as? String ?? tab.title, chapterStart: headingID != nil)
                } catch { }
            }
        }

        func findIfNeeded(force: Bool = false) {
            guard loaded, !rendering, state.error == nil, let webView else { return }
            let search = tab.markdownFind
            guard force || lastFindRequest != search.request else { return }
            let initial = lastFindRequest == nil
            let query = search.query
            let request = search.request
            let move = !force && !initial && search.direction != 0 && lastFindQuery == query
            let direction = search.direction
            let scroll = (!force && !initial) || (search.busy && search.current == 0)
            var index = (force || initial) ? max(0, search.current - 1) : 0
            if (force || initial) && search.busy && search.current > 0 && direction != 0 { index += direction }
            lastFindRequest = request; lastFindQuery = query
            findTask?.cancel()
            findRevision += 1
            let current = findRevision
            let documentRevision = revision
            findTask = Task { [weak self, weak webView] in
                guard let self, let webView else { return }
                do {
                    if !move && !force && !query.isEmpty { try await Task.sleep(for: .milliseconds(150)) }
                    try Task.checkCancellation()
                    if !query.isEmpty { search.busy = true }
                    let result = try await webView.callAsyncJavaScript(
                        "return move ? window.luma.moveSearch(direction, {request}) : window.luma.findText(query, {index, scroll, request});",
                        arguments: ["move": move, "direction": direction, "query": query, "index": index, "scroll": scroll, "request": request],
                        in: nil, contentWorld: .page
                    )
                    guard !Task.isCancelled, current == findRevision, documentRevision == revision, search.request == request, search.query == query else { return }
                    if let values = result as? [String: Any] { search.apply(values) }
                } catch {
                    guard !Task.isCancelled, current == findRevision, documentRevision == revision, search.request == request else { return }
                    search.busy = false; search.count = 0; search.current = 0; search.error = error.localizedDescription
                }
            }
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.frameInfo.isMainFrame, let body = message.body as? [String: Any], let kind = body["kind"] as? String else { return }
            switch kind {
            case "find":
                guard !rendering, body["query"] as? String == tab.markdownFind.query,
                      body["request"] as? Int == tab.markdownFind.request else { return }
                tab.markdownFind.apply(body)
            case "outline":
                guard let values = body["headings"] as? [[String: Any]], values.count <= 2_000 else { return }
                state.headings = values.compactMap { value in
                    guard let id = value["id"] as? String, !id.isEmpty, id.count <= 200,
                          let title = value["title"] as? String, let level = value["level"] as? Int, (1...6).contains(level) else { return nil }
                    let summary = value["summary"] as? String ?? ""
                    return MarkdownHeading(id: id, title: String(title.prefix(240)), level: level,
                                           summary: String(summary.prefix(161)))
                }
                state.outlineTruncated = body["truncated"] as? Bool ?? false
                tab.markdownCollapsedHeadings.formIntersection(Set(state.headings.map(\.id)))
            case "section":
                state.activeHeadingID = (body["id"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            case "position":
                guard tab.markdownCaptureID == captureID else { return }
                if let value = body["location"] as? [String: Any], let position = MarkdownReadingLocation(message: value) { tab.rememberReadingPosition(position) }
                else if let offset = body["offset"] as? Double, offset.isFinite { tab.markdownOffset = max(0, offset) }
            case "copy":
                guard let text = body["text"] as? String, text.utf8.count <= 4 * 1_024 * 1_024 else { return }
                NSPasteboard.general.clearContents(); NSPasteboard.general.setString(text, forType: .string)
            case "link":
                guard let href = body["href"] as? String, let url = URL(string: href, relativeTo: tab.url)?.absoluteURL else { return }
                if url.isFileURL { onOpen([url]) }
                else if ["http", "https", "mailto"].contains(url.scheme?.lowercased() ?? "") { NSWorkspace.shared.open(url) }
            default: break
            }
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
            let url = navigationAction.request.url
            return url?.scheme == "luma-preview" && url?.host == "reader" && url?.path == "/index.html" ? .allow : .cancel
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: any Error) {
            state.loading = false; state.error = error.localizedDescription
        }
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: any Error) {
            state.loading = false; state.error = error.localizedDescription
        }
        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            loaded = false; state.loading = false; state.error = "预览进程已退出。请重新载入文件，或切换到源码。"
        }
    }
}
