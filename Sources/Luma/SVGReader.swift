import SwiftUI
import WebKit
import ReaderCore

@Observable final class SVGRenderState {
    var loading = true
    var error: String?
    var size: CGSize?
}

struct SVGReader: View {
    let source: String
    @Bindable var tab: DocumentTab
    @Environment(\.colorScheme) private var colorScheme
    @ViewState private var state = SVGRenderState()

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                SVGWebView(source: source, zoom: tab.zoom, dark: colorScheme == .dark, state: state, actualSize: tab.imageActualSize, language: AppLocalization.shared.language)
                    .opacity(state.error == nil ? 1 : 0)
                if state.loading { ProgressView(tr("正在打开 SVG…")) }
                if let error = state.error {
                    VStack(spacing: 12) {
                        Text(tr("暂时无法生成 SVG 预览")).font(.headline)
                        Text(error).font(.callout).foregroundStyle(.secondary)
                        Button(tr("查看源码")) { tab.showSource = true }
                            .buttonStyle(LumaButtonStyle(emphasis: .secondary))
                    }.padding(32)
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
            LumaRule()
            HStack(spacing: 6) {
                Text(tr("SVG · 矢量预览")).font(.caption).foregroundStyle(LumaTheme.muted)
                Spacer()
                Button { tab.zoom = max(0.25, tab.zoom / 1.25) } label: { Image(systemName: "minus.magnifyingglass") }
                    .help(tr("缩小")).accessibilityLabel(tr("缩小"))
                Button(tr("适合窗口")) { tab.imageActualSize = false; tab.zoom = 1 }
                Button(tr("按文字大小")) { tab.imageActualSize = true; tab.zoom = 1 }
                Button { tab.zoom = min(8, tab.zoom * 1.25) } label: { Image(systemName: "plus.magnifyingglass") }
                    .help(tr("放大")).accessibilityLabel(tr("放大"))
            }.buttonStyle(LumaButtonStyle()).padding(.horizontal, 12).padding(.vertical, 4)
                .background(LumaTheme.chrome)
        }
    }
}

/// The file is only ever an image data URL. It cannot become markup in the host document.
struct SVGWebView: NSViewRepresentable {
    let source: String
    let zoom: Double
    let dark: Bool
    let state: SVGRenderState
    var actualSize = false
    var language: AppLanguage = .simplifiedChinese

    func makeCoordinator() -> Coordinator { Coordinator(state: state) }
    func makeNSView(context: Context) -> WKWebView {
        let view = Self.makeWebView(coordinator: context.coordinator)
        context.coordinator.update(source: source, zoom: zoom, dark: dark, actualSize: actualSize, language: language)
        return view
    }
    func updateNSView(_ view: WKWebView, context: Context) {
        context.coordinator.update(source: source, zoom: zoom, dark: dark, actualSize: actualSize, language: language)
    }
    static func makeWebView(coordinator: Coordinator) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.userContentController.add(coordinator, name: "svg")
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.navigationDelegate = coordinator
        view.underPageBackgroundColor = LumaTheme.nativePaper
        coordinator.webView = view
        return view
    }
    static func dismantleNSView(_ view: WKWebView, coordinator: Coordinator) {
        view.stopLoading()
        view.configuration.userContentController.removeScriptMessageHandler(forName: "svg")
        view.navigationDelegate = nil
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        let state: SVGRenderState
        weak var webView: WKWebView?
        private var source: String?
        private var zoom = 1.0
        private var dark = false
        private var actualSize = false
        private var language = AppLanguage.simplifiedChinese
        private var revision = ""
        private var navigation: WKNavigation?

        init(state: SVGRenderState) { self.state = state }

        func update(source: String, zoom: Double, dark: Bool, actualSize: Bool = false, language: AppLanguage = .simplifiedChinese) {
            let changedAppearance = self.zoom != zoom || self.dark != dark || self.actualSize != actualSize
            self.zoom = zoom; self.dark = dark; self.actualSize = actualSize
            let languageChanged = self.language != language
            self.language = language
            if self.source != source || languageChanged {
                self.source = source
                revision = UUID().uuidString
                state.loading = true; state.error = nil; state.size = nil
                navigation = webView?.loadHTMLString(Self.html(source: source, zoom: zoom, dark: dark, revision: revision, actualSize: actualSize, language: language), baseURL: nil)
            } else if changedAppearance { updateAppearance() }
        }

        private func updateAppearance() {
            webView?.evaluateJavaScript("window.setView?.(\(zoom), \(dark ? "true" : "false"), \(actualSize ? "true" : "false"))", completionHandler: nil)
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.frameInfo.isMainFrame, let body = message.body as? [String: Any],
                  body["revision"] as? String == revision else { return }
            state.loading = false
            if let width = body["width"] as? Double, let height = body["height"] as? Double,
               width.isFinite, height.isFinite, width > 0, height > 0 {
                state.size = CGSize(width: width, height: height)
                state.error = nil
            } else {
                state.error = tr("SVG 无法显示，可以切换到源码检查文件内容。")
            }
        }

        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction) async -> WKNavigationActionPolicy {
            action.navigationType == .other && action.request.url?.absoluteString == "about:blank" ? .allow : .cancel
        }
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { updateAppearance() }
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: any Error) {
            guard navigation === self.navigation else { return }
            state.loading = false; state.error = error.localizedDescription
        }
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: any Error) {
            guard navigation === self.navigation else { return }
            state.loading = false; state.error = error.localizedDescription
        }
        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            state.loading = false; state.error = tr("预览进程已退出。请切换到源码，或重新载入文件。")
        }

        private static func html(source: String, zoom: Double, dark: Bool, revision: String, actualSize: Bool, language: AppLanguage) -> String {
            let encoded = Data(source.utf8).base64EncodedString()
            return #"""
            <!doctype html>
            <html lang="\#(language.rawValue)" data-dark="\#(dark)"><head><meta charset="utf-8">
            <meta http-equiv="Content-Security-Policy" content="default-src 'none'; img-src data:; style-src 'unsafe-inline'; script-src 'nonce-\#(revision)'; base-uri 'none'; form-action 'none'">
            <style>
              :root { color-scheme: light; background: #FCFCFA; }
              :root[data-dark="true"] { color-scheme: dark; background: #1A202B; }
              * { box-sizing: border-box; }
              html, body { margin: 0; min-width: 100%; min-height: 100%; }
              main { display: grid; place-items: center; min-width: 100vw; min-height: 100vh; padding: 32px; width: max-content; }
              img { display: block; background-color: transparent;
                background-image: conic-gradient(rgba(128,128,128,.16) 25%, transparent 0 50%, rgba(128,128,128,.16) 0 75%, transparent 0);
                background-size: 16px 16px; }
            </style></head><body><main><img alt="\#(ReaderLocalization.text(key: "SVG 图像", language: language))" src="data:image/svg+xml;base64,\#(encoded)"></main>
            <script nonce="\#(revision)">
              const image = document.querySelector('img');
              let zoom = \#(zoom), actualSize = \#(actualSize);
              function resize() {
                if (!image.naturalWidth || !image.naturalHeight) return;
                const fit = Math.max(.01, Math.min((innerWidth - 64) / image.naturalWidth, (innerHeight - 64) / image.naturalHeight, 1));
                image.style.width = (image.naturalWidth * (actualSize ? 1 : fit) * zoom) + 'px';
                image.style.height = (image.naturalHeight * (actualSize ? 1 : fit) * zoom) + 'px';
              }
              window.setView = (value, dark, actual = false) => { zoom = value; actualSize = actual; document.documentElement.dataset.dark = dark; resize(); };
              function report() {
                resize();
                window.webkit.messageHandlers.svg.postMessage({revision: '\#(revision)', width: image.naturalWidth, height: image.naturalHeight});
              }
              image.addEventListener('load', report);
              image.addEventListener('error', report);
              window.addEventListener('resize', resize);
              if (image.complete) report();
            </script></body></html>
            """#
        }
    }
}
