import AppKit
import SwiftUI
import WebKit
import Testing
@testable import Luma

@MainActor @Suite(.serialized) struct SVGPreviewTests {
    private let source = ##"<svg xmlns="http://www.w3.org/2000/svg" width="400" height="240" viewBox="0 0 400 240"><rect x="20" y="20" width="360" height="200" rx="24" fill="#3A6095"/><circle cx="200" cy="120" r="60" fill="#FCFCFA"/><text x="200" y="128" text-anchor="middle" font-size="22" fill="#3A6095">Luma</text></svg>"##

    @MainActor private struct Preview {
        let view: WKWebView
        let coordinator: SVGWebView.Coordinator
        let state: SVGRenderState
        func value(_ script: String) async throws -> Any? { try await view.evaluateJavaScript(script) }
        func close() { SVGWebView.dismantleNSView(view, coordinator: coordinator) }
        func snapshot(_ name: String) async throws {
            guard let path = ProcessInfo.processInfo.environment["LUMA_SVG_PREVIEW_DIR"] else { return }
            let image = try await view.takeSnapshot(configuration: nil)
            let bitmap = try #require(image.tiffRepresentation.flatMap(NSBitmapImageRep.init(data:)))
            let data = try #require(bitmap.representation(using: .png, properties: [:]))
            let folder = URL(fileURLWithPath: path)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try data.write(to: folder.appendingPathComponent(name + ".png"))
        }
    }

    private func render(_ source: String, zoom: Double = 1, dark: Bool = false) async throws -> Preview {
        _ = NSApplication.shared
        let state = SVGRenderState()
        let coordinator = SVGWebView.Coordinator(state: state)
        let view = SVGWebView.makeWebView(coordinator: coordinator)
        view.frame = NSRect(x: 0, y: 0, width: 800, height: 600)
        let preview = Preview(view: view, coordinator: coordinator, state: state)
        coordinator.update(source: source, zoom: zoom, dark: dark)
        do { try await wait(preview); return preview }
        catch { preview.close(); throw error }
    }
    private func wait(_ preview: Preview) async throws {
        let deadline = ContinuousClock.now + .seconds(15)
        while preview.state.loading && ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(20)) }
        try #require(!preview.state.loading, "SVG render timed out")
    }

    @Test func vectorRendersWithTransparencyZoomAndBothAppearances() async throws {
        let preview = try await render(source)
        defer { preview.close() }
        #expect(preview.state.error == nil && preview.state.size == CGSize(width: 400, height: 240))
        #expect(try await preview.value("document.querySelector('img').naturalWidth") as? Int == 400)
        #expect(try await preview.value("getComputedStyle(document.querySelector('img')).backgroundImage.includes('conic-gradient')") as? Bool == true)
        #expect(try await preview.value("getComputedStyle(document.documentElement).backgroundColor") as? String == "rgb(252, 252, 250)")
        try await preview.snapshot("svg-light")
        preview.coordinator.update(source: source, zoom: 2, dark: true)
        let deadline = ContinuousClock.now + .seconds(5)
        while ContinuousClock.now < deadline {
            if try await preview.value("document.querySelector('img').style.width") as? String == "800px" { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(try await preview.value("document.querySelector('img').style.width") as? String == "800px")
        #expect(try await preview.value("document.documentElement.dataset.dark") as? String == "true")
        #expect(try await preview.value("getComputedStyle(document.documentElement).backgroundColor") as? String == "rgb(26, 32, 43)")
        preview.coordinator.update(source: source, zoom: 1, dark: true)
        _ = try await preview.value("window.setView(1, true)")
        try await preview.snapshot("svg-dark")
        preview.view.frame = NSRect(x: 0, y: 0, width: 320, height: 420)
        let narrowDeadline = ContinuousClock.now + .seconds(5)
        while ContinuousClock.now < narrowDeadline {
            if try await preview.value("document.querySelector('img').clientWidth") as? Int == 256 { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(try await preview.value("document.querySelector('img').clientWidth") as? Int == 256)
        try await preview.snapshot("svg-narrow")
    }

    @Test func naturalTextSizeCanBeRestoredAfterFittingNarrowWindow() async throws {
        let preview = try await render(source)
        defer { preview.close() }
        preview.view.frame = NSRect(x: 0, y: 0, width: 240, height: 400)
        _ = try await preview.value("window.setView(1, false, false)")
        #expect(try await preview.value("document.querySelector('img').clientWidth") as? Int == 176)
        preview.coordinator.update(source: source, zoom: 1, dark: false, actualSize: true)
        let deadline = ContinuousClock.now + .seconds(3)
        while ContinuousClock.now < deadline {
            if try await preview.value("document.querySelector('img').clientWidth") as? Int == 400 { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(try await preview.value("document.querySelector('img').clientWidth") as? Int == 400)
        #expect(try await preview.value("document.documentElement.scrollWidth > innerWidth") as? Bool == true)
        preview.coordinator.update(source: source, zoom: 1, dark: false, actualSize: false)
        _ = try await preview.value("window.setView(1, false, false)")
        #expect(try await preview.value("document.querySelector('img').clientWidth") as? Int == 176)
    }

    @Test(arguments: [("图片资源/阅读 流程.svg", 760, 180)])
    func bundledSVGAlsoWorksAsAnIndependentDocument(path: String, width: Int, height: Int) async throws {
        let domain = "local.luma.svg-sample.\(UUID())"
        let preferences = try #require(UserDefaults(suiteName: domain))
        defer { preferences.removePersistentDomain(forName: domain) }
        let workspace = chineseWorkspace(preferences: preferences)
        let file = try #require(workspace.samplesURL).appendingPathComponent(path)
        workspace.open([file])
        let tab = try #require(workspace.activeTab)
        await tab.loadTask?.value
        guard case .ready(.svg(let source)) = tab.state else { Issue.record("Sample SVG did not open"); return }
        let preview = try await render(source)
        defer { preview.close() }
        #expect(preview.state.error == nil && preview.state.size == CGSize(width: width, height: height))
        try await preview.snapshot("svg-sample-" + file.deletingPathExtension().lastPathComponent)
    }

    @Test func hostileSVGStaysInsideAnInertImage() async throws {
        let hostile = #"""
        <svg xmlns="http://www.w3.org/2000/svg" width="200" height="100" onload="parent.document.documentElement.dataset.executed='yes'">
          <script>parent.document.documentElement.dataset.executed='yes';</script>
          <foreignObject width="100" height="100"><div xmlns="http://www.w3.org/1999/xhtml"><img src="https://example.invalid/tracker" onerror="parent.document.documentElement.dataset.executed='yes'"/></div></foreignObject>
          <rect width="100" height="100" fill="blue"/>
        </svg>
        """#
        let preview = try await render(hostile)
        defer { preview.close() }
        #expect(preview.state.error == nil)
        #expect(try await preview.value("document.documentElement.dataset.executed === undefined") as? Bool == true)
        #expect(try await preview.value("document.querySelectorAll('svg, foreignObject, iframe, object').length") as? Int == 0)
        #expect(try await preview.value("document.querySelectorAll('img').length") as? Int == 1)
        #expect(try await preview.value("document.querySelector('img').src.startsWith('data:image/svg+xml;base64,')") as? Bool == true)
        #expect(try await preview.value("document.querySelector('meta[http-equiv]').content.includes(\"default-src 'none'\")") as? Bool == true)
        #expect(try await preview.value("performance.getEntriesByType('resource').every(entry => !/^https?:|^file:/.test(entry.name))") as? Bool == true)
        #expect(preview.view.configuration.websiteDataStore.isPersistent == false)
        #expect(try await preview.value("document.querySelectorAll('script').length") as? Int == 1)
    }

    @Test func failedImageAndRapidDraftChangesRecover() async throws {
        let preview = try await render("<svg")
        defer { preview.close() }
        #expect(preview.state.error != nil)
        preview.coordinator.update(source: source.replacingOccurrences(of: "400", with: "500"), zoom: 1, dark: false)
        preview.coordinator.update(source: source, zoom: 1.25, dark: true)
        try await wait(preview)
        #expect(preview.state.error == nil && preview.state.size == CGSize(width: 400, height: 240))
        #expect(try await preview.value("document.querySelector('img').style.width") as? String == "500px")
        #expect(try await preview.value("document.documentElement.dataset.dark") as? String == "true")
    }

    @Test func actualDocumentViewSwitchesBetweenSVGAndEditableDraft() async throws {
        _ = NSApplication.shared
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID()).svg")
        let domain = "local.luma.svg-ui.\(UUID())"
        let preferences = try #require(UserDefaults(suiteName: domain))
        defer { try? FileManager.default.removeItem(at: file); preferences.removePersistentDomain(forName: domain) }
        try Data(source.utf8).write(to: file)
        let workspace = chineseWorkspace(preferences: preferences)
        workspace.open([file])
        let tab = try #require(workspace.activeTab)
        await tab.loadTask?.value
        let host = NSHostingController(rootView: DocumentView(tab: tab, workspace: workspace).frame(width: 800, height: 600))
        let window = NSWindow(contentViewController: host)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        func webView(in view: NSView) -> WKWebView? {
            if let view = view as? WKWebView { return view }
            return view.subviews.lazy.compactMap { webView(in: $0) }.first
        }
        func imageSource() async throws -> String? {
            let deadline = ContinuousClock.now + .seconds(15)
            while ContinuousClock.now < deadline {
                host.view.layoutSubtreeIfNeeded()
                if let web = webView(in: host.view),
                   let value = try? await web.evaluateJavaScript("document.querySelector('img')?.src") as? String { return value }
                try await Task.sleep(for: .milliseconds(20))
            }
            return nil
        }
        #expect(try await imageSource()?.contains(Data(source.utf8).base64EncodedString()) == true)
        #expect(tab.editor == nil)
        tab.showSource = true
        let deadline = ContinuousClock.now + .seconds(5)
        while tab.editor == nil && ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(20)) }
        let editor = try #require(tab.editor)
        editor.textView.insertText("\n", replacementRange: NSRange(location: 0, length: 0))
        editor.textView.breakUndoCoalescing()
        await tab.previewTask?.value
        tab.showSource = false
        let changed = try #require(tab.draft)
        #expect(try await imageSource()?.contains(Data(changed.utf8).base64EncodedString()) == true)
        #expect(tab.isDirty && tab.canUndo)
        #expect(await workspace.save(tab))
        #expect(try String(contentsOf: file, encoding: .utf8) == changed)
        tab.showSource = true
        #expect(tab.sourceEditor() === editor && tab.canUndo)
    }
}
