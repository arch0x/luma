import AppKit
import WebKit
import Testing
@testable import Luma

@MainActor @Suite(.serialized) struct MarkdownPreviewTests {
    @MainActor struct Preview {
        let view: WKWebView
        let coordinator: MarkdownWebView.Coordinator
        let state: MarkdownRenderState
        func close() { MarkdownWebView.dismantleNSView(view, coordinator: coordinator) }
        func value(_ script: String) async throws -> Any? { try await view.evaluateJavaScript(script) }
    }

    private func render(_ source: String, dark: Bool = false, document: URL? = nil, imageRoot: URL? = nil,
                        width: Double = 0, typography: MarkdownTypography = .init(), location: MarkdownReadingLocation? = nil, session: MarkdownReadingSession? = nil) async throws -> Preview {
        _ = NSApplication.shared
        let state = MarkdownRenderState()
        let tab = DocumentTab(url: document ?? URL(fileURLWithPath: "/tmp/preview.md"), readingSession: session)
        if let location { tab.rememberReadingPosition(location) }
        let coordinator = MarkdownWebView.Coordinator(source: source, tab: tab, imageRoot: imageRoot, previewWidth: width, typography: typography, dark: dark, state: state, onOpen: { _ in }, language: .simplifiedChinese)
        let view = MarkdownWebView.makeWebView(coordinator: coordinator)
        view.frame = NSRect(x: 0, y: 0, width: 1000, height: 800)
        let preview = Preview(view: view, coordinator: coordinator, state: state)
        do {
            try await wait(preview)
            return preview
        } catch {
            preview.close()
            throw error
        }
    }

    private func wait(_ preview: Preview) async throws {
        let deadline = ContinuousClock.now + .seconds(20)
        while preview.state.loading && ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(25)) }
        try #require(!preview.state.loading, "WebKit render timed out")
        try #require(preview.state.error == nil, "\(preview.state.error ?? "")")
    }

    @Test func tablesSupportAlignmentInlineFormattingAndEscapedPipes() async throws {
        let preview = try await render("""
        | 左列 | 中列 | 右列 |
        | :--- | :---: | ---: |
        | **重点** | a\\|b | 42 |
        """)
        defer { preview.close() }
        #expect(preview.state.metrics["tables"] == 1)
        #expect(try await preview.value("document.querySelectorAll('td').length") as? Int == 3)
        #expect(try await preview.value("document.querySelector('td strong').textContent") as? String == "重点")
        #expect(try await preview.value("document.querySelectorAll('td')[1].textContent") as? String == "a|b")
        #expect(try await preview.value("getComputedStyle(document.querySelectorAll('td')[2]).textAlign") as? String == "right")
    }

    @Test func fencesHighlightSwiftAndKeepOtherLanguagesReadable() async throws {
        let preview = try await render("""
        ```swift
        struct Note { let title = "你好" }
        ```
        ```unknown-language
        <script>neverRun()</script>
        ```
        """)
        defer { preview.close() }
        #expect(preview.state.metrics["highlighted"] == 1)
        #expect(try await preview.value("document.querySelector('.hljs-keyword').textContent") as? String == "struct")
        #expect(try await preview.value("document.querySelectorAll('pre code')[1].textContent") as? String == "<script>neverRun()</script>")
        #expect(try await preview.value("document.querySelector('main script') === null") as? Bool == true)
    }

    @Test func mermaidRendersFlowchartAndSequenceOffline() async throws {
        let preview = try await render("""
        ```mermaid
        flowchart LR
          A[文档] --> B{格式}
          B --> C[阅读]
        ```
        ```mermaid
        sequenceDiagram
          Alice->>Bob: Hello
          Bob-->>Alice: Hi
        ```
        """)
        defer { preview.close() }
        #expect(preview.state.metrics["diagrams"] == 2)
        #expect(preview.state.metrics["failures"] == 0)
        #expect(try await preview.value("document.querySelectorAll('.diagram-canvas svg').length") as? Int == 2)
        #expect(try await preview.value("document.querySelector('.diagram-canvas svg').getAttribute('viewBox') !== null") as? Bool == true)
    }

    @Test(arguments: [
        ("typescript", "interface Note { title: string }"),
        ("rust", "fn main() { let name = \"Luma\"; }"),
        ("python", "def read(path):\n    return path.read_text()"),
        ("javascript", "const name = \"Luma\";"),
        ("json", "{\"ready\": true}")
    ])
    func registeredLanguagesProduceRealHighlightSpans(language: String, code: String) async throws {
        let preview = try await render("```\(language)\n\(code)\n```")
        defer { preview.close() }
        #expect(preview.state.metrics["highlighted"] == 1)
        #expect(try await preview.value("document.querySelector('pre code span') !== null") as? Bool == true)
        #expect(try await preview.value("document.querySelector('pre code').textContent") as? String == code)
    }

    @Test func invalidMermaidPreservesSourceAndOtherContent() async throws {
        let preview = try await render("""
        ```mermaid
        flowchart LR
          A --> [
        ```
        ## Still readable
        """)
        defer { preview.close() }
        #expect(preview.state.metrics["failures"] == 1)
        #expect(try await preview.value("document.querySelector('details').open") as? Bool == true)
        #expect(try await preview.value("document.querySelector('details pre').textContent.includes('A --> [')") as? Bool == true)
        #expect(try await preview.value("document.querySelector('h2').textContent") as? String == "Still readable")
    }

    @Test func rawHTMLAndHostileLinksNeverBecomeExecutableMarkup() async throws {
        let preview = try await render("""
        <script>window.untrusted = 1</script>

        <img src="https://example.invalid/pixel" onerror="window.untrusted = 2">

        [bad](javascript:alert(1))

        ![remote](https://example.invalid/track.png)
        """)
        defer { preview.close() }
        #expect(try await preview.value("window.untrusted === undefined") as? Bool == true)
        #expect(try await preview.value("document.querySelectorAll('main script, main img, main iframe').length") as? Int == 0)
        #expect(try await preview.value("document.querySelector('main a[href^=\"javascript:\"]') === null") as? Bool == true)
        #expect(try await preview.value("document.querySelector('main').textContent.includes('<script>')") as? Bool == true)
    }

    @Test func themeUpdatesRerenderMermaidAndCodeColors() async throws {
        let preview = try await render("```mermaid\ngraph LR\nA-->B\n```\n\n```json\n{\"ok\":true}\n```", dark: false)
        defer { preview.close() }
        let lightColor = try await preview.value("getComputedStyle(document.querySelector('.hljs-literal')).color") as? String
        preview.coordinator.dark = true
        preview.coordinator.renderIfNeeded()
        await preview.coordinator.renderTask?.value
        try #require(preview.state.error == nil)
        #expect(try await preview.value("document.documentElement.dataset.theme") as? String == "dark")
        #expect(preview.state.metrics["diagrams"] == 1)
        #expect(try await preview.value("getComputedStyle(document.querySelector('.hljs-literal')).color") as? String != lightColor)
    }

    @Test(arguments: [false, true])
    func linksAndSelectionUseBlueWhileFindUsesAmber(dark: Bool) async throws {
        let preview = try await render("# 阅读\n\n[needle](#阅读) 与正文 needle", dark: dark)
        defer { preview.close() }
        _ = try await find("needle", in: preview)
        let channels = try await preview.value("""
        [getComputedStyle(document.querySelector('a')).color,
         getComputedStyle(document.querySelector('p'), '::selection').backgroundColor,
         getComputedStyle(document.querySelector('.search-hit-current')).backgroundColor]
          .map(color => color.match(/[\\d.]+/g).slice(0, 3).map(Number))
        """) as? [[Double]]
        let colors = try #require(channels)
        try #require(colors.count == 3 && colors.allSatisfy { $0.count == 3 })
        #expect(colors[0][2] > colors[0][1] && colors[0][1] > colors[0][0])
        #expect(colors[1][2] > colors[1][1] && colors[1][1] > colors[1][0])
        #expect(colors[2][0] > colors[2][1] && colors[2][1] > colors[2][2])
    }

    @Test func resourceHandlerCannotReadDocumentOrParentPaths() {
        for value in ["luma-preview://reader/../Workspace.swift", "luma-preview://reader/%2e%2e/Workspace.swift", "luma-preview://other/index.html", "file:///etc/passwd"] {
            #expect(throws: (any Error).self) { try MarkdownResources.resource(for: #require(URL(string: value))) }
        }
    }

    @Test func mathSupportsFourDelimitersAndLoadsBundledFonts() async throws {
        let preview = try await render(#"""
        行内 $E = mc^2$，还有 \(\frac{1}{2}\)。

        $$
        \sum_{i=1}^{n} i = \frac{n(n+1)}{2}
        $$

        \[
        \begin{pmatrix} a & b \\ c & d \end{pmatrix}
        \]
        """#)
        defer { preview.close() }
        #expect(preview.state.metrics["formulas"] == 4)
        #expect(preview.state.metrics["mathFailures"] == 0)
        #expect(try await preview.value("document.querySelectorAll('.katex-display').length") as? Int == 2)
        #expect(try await preview.value("document.querySelectorAll('.katex math').length") as? Int == 4)
        #expect(try await preview.value("[...document.fonts].some(font => font.family.startsWith('KaTeX_') && font.status === 'loaded')") as? Bool == true)
        #expect(try await preview.value("[...document.fonts].filter(font => font.family.startsWith('KaTeX_') && font.status === 'error').length") as? Int == 0)
    }

    @Test func mathDoesNotConsumeCodeEscapesOrCurrency() async throws {
        let preview = try await render(#"""
        Cost $5 and $10. Escaped \$x\$. Code `$x$` and `\(x\)`.

        ```latex
        $$x^2$$
        \[y^2\]
        ```
        """#)
        defer { preview.close() }
        #expect(preview.state.metrics["formulas"] == 0)
        #expect(try await preview.value("document.querySelector('main').textContent.includes('Cost $5 and $10')") as? Bool == true)
        #expect(try await preview.value("document.querySelector('pre code').textContent.includes('$$x^2$$')") as? Bool == true)
    }

    @Test func invalidMathKeepsSourceAndDoesNotLeakMacrosOrTrustedHTML() async throws {
        let preview = try await render(#"""
        $\notARealCommand{x}$

        $\gdef\privateMacro{x}\privateMacro$

        $\privateMacro$

        $\href{javascript:alert(1)}{click}$

        $\includegraphics{https://example.invalid/track.png}$

        ## Still readable
        """#)
        defer { preview.close() }
        #expect(preview.state.metrics["mathFailures"] == 2)
        #expect(try await preview.value("document.querySelector('.math-error').textContent.includes('notARealCommand')") as? Bool == true)
        #expect(try await preview.value("document.querySelectorAll('main a:not(.heading-anchor), main img, main iframe').length") as? Int == 0)
        #expect(try await preview.value("document.querySelector('h2').textContent") as? String == "Still readable")
    }

    @Test func localImagesResolveUnicodeSpacesEncodedPathsAndWorkspaceParents() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let assets = directory.appendingPathComponent("assets")
        let docs = directory.appendingPathComponent("docs")
        try FileManager.default.createDirectory(at: assets, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: docs, withIntermediateDirectories: true)
        let sample = try #require(chineseWorkspace().samplesURL).appendingPathComponent("留白.png")
        try FileManager.default.copyItem(at: sample, to: assets.appendingPathComponent("中文 空格.png"))
        try FileManager.default.copyItem(at: sample, to: assets.appendingPathComponent("100% 留白.png"))
        let preview = try await render("""
        ![中文路径](<../assets/中文 空格.png>)

        ![编码路径](../assets/中文%20空格.png)

        ![绝对路径](\(assets.appendingPathComponent("中文 空格.png").absoluteString))

        ![百分号](<../assets/100% 留白.png>)
        """, document: docs.appendingPathComponent("note.md"), imageRoot: directory)
        defer { preview.close() }
        let failure = try await preview.value("[...document.querySelectorAll('.image-failed')].map(node => node.textContent).join('; ')") as? String ?? ""
        #expect(preview.state.metrics["images"] == 4, "\(failure)")
        #expect(preview.state.metrics["imageFailures"] == 0)
        #expect(try await preview.value("[...document.querySelectorAll('main img')].every(img => img.complete && img.naturalWidth === 1200)") as? Bool == true)
    }

    @Test func svgLoadsAsImageAndMissingOrRemoteImagesHaveVisibleFallbacks() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try #"<svg xmlns="http://www.w3.org/2000/svg" width="80" height="40"><rect width="80" height="40" fill="green"/></svg>"#.write(to: directory.appendingPathComponent("shape.svg"), atomically: true, encoding: .utf8)
        let preview = try await render("![矢量图](shape.svg)\n\n![缺失](missing.png)\n\n![远程](https://example.invalid/track.png)", document: directory.appendingPathComponent("note.md"))
        defer { preview.close() }
        #expect(preview.state.metrics["images"] == 1)
        #expect(preview.state.metrics["imageFailures"] == 2)
        #expect(try await preview.value("document.querySelector('main img').naturalWidth") as? Int == 80)
        #expect(try await preview.value("document.querySelectorAll('.image-failed').length") as? Int == 2)
        #expect(try await preview.value("document.querySelector('.image-failed').textContent.includes('missing.png')") as? Bool == true)
    }

    @Test func imageScopeRejectsTraversalSymlinksAndOtherSchemes() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let root = directory.appendingPathComponent("root")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let outside = directory.appendingPathComponent("private.png")
        try Data("private".utf8).write(to: outside)
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("escape.png"), withDestinationURL: outside)
        for path in ["../private.png", "%2e%2e/private.png", "escape.png", "https://example.invalid/a.png", "//server/a.png", "data:image/png;base64,AA=="] {
            #expect(throws: (any Error).self) {
                try MarkdownImageLocation.resolve(path, document: root.appendingPathComponent("note.md"), root: root)
            }
        }
    }

    @Test func imageLoaderBoundsLargeRasterAndEncodedSVG() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let large = directory.appendingPathComponent("large.png")
        try Data().write(to: large)
        let file = try FileHandle(forWritingTo: large)
        try file.truncate(atOffset: UInt64(MarkdownImageLoader.fileLimit + 1))
        try file.close()
        try #"<!DOCTYPE svg [<!ENTITY data SYSTEM "file:///etc/passwd">]><svg xmlns="http://www.w3.org/2000/svg"/>"#.write(to: directory.appendingPathComponent("entity.svg"), atomically: true, encoding: .utf8)
        let loader = MarkdownImageLoader(document: directory.appendingPathComponent("note.md"), root: directory)
        await #expect(throws: (any Error).self) { try await loader.image("large.png") }
        await #expect(throws: (any Error).self) { try await loader.image("entity.svg") }
    }

    @Test func bundledImageAndMathSampleRendersTogether() async throws {
        let folder = try #require(chineseWorkspace().samplesURL)
        let file = folder.appendingPathComponent("图片与公式.md")
        let source = try String(contentsOf: file, encoding: .utf8)
        let preview = try await render(source, document: file, imageRoot: folder)
        defer { preview.close() }
        #expect(preview.state.metrics["images"] == 2)
        #expect(preview.state.metrics["imageFailures"] == 1)
        #expect(preview.state.metrics["formulas"] == 6)
        #expect(preview.state.metrics["mathFailures"] == 1)
        #expect(try await preview.value("document.querySelector('table .katex') !== null") as? Bool == true)
    }

    @Test func bundledFormatGuideRendersEveryCatalogEntry() async throws {
        let folder = try #require(chineseWorkspace().samplesURL)
        let file = folder.appendingPathComponent("格式示例/格式导览.md")
        let source = try String(contentsOf: file, encoding: .utf8)
        let preview = try await render(source, document: file, imageRoot: folder, width: 840)
        defer { preview.close() }
        let formats = try SampleWorkspace.formats()
        #expect(preview.state.metrics["tables"] == Set(formats.map(\.section)).count)
        #expect(try await preview.value("document.querySelectorAll('table tbody tr').length") as? Int == formats.count)
        #expect(try await preview.value("document.querySelectorAll('.raw-html').length") as? Int == 0)
        #expect(try await preview.value("getComputedStyle(document.querySelector('main a')).color") as? String == "rgb(58, 96, 149)")
        let snapshot = CodePreviewTests.Preview(view: preview.view, coordinator: preview.coordinator, state: preview.state)
        try await snapshot.snapshot("sample-format-catalog")
    }

    private func waitForSection(_ preview: Preview, id: String) async throws {
        let deadline = ContinuousClock.now + .seconds(2)
        while preview.state.activeHeadingID != id && ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(20)) }
        try #require(preview.state.activeHeadingID == id)
    }

    @Test func outlineHandlesHeadingLevelsDuplicatesUnicodeAndCodeExclusion() async throws {
        let preview = try await render(#"""
        # 文档 **概览**
        ## 重复
        ### 重复
        ## 重复-1
        #### 跳级
        ##### 五级
        ###### 六级
        ## !!!
        ## 🙂
        ## Energy $E=mc^2$

        ```markdown
        # Not a heading
        ```

        <h2>Not trusted HTML</h2>
        """#)
        defer { preview.close() }
        #expect(preview.state.headings.map(\.level) == [1, 2, 3, 2, 4, 5, 6, 2, 2, 2])
        #expect(preview.state.headings.first?.title == "文档 概览")
        #expect(Array(preview.state.headings.prefix(4)).map(\.id) == ["文档-概览", "重复", "重复-1", "重复-1-1"])
        #expect(Set(preview.state.headings.map(\.id)).count == 10)
        #expect(preview.state.headings[7].id == "section")
        #expect(preview.state.headings[8].id == "section-1")
        #expect(preview.state.headings.last?.title == "Energy E=mc^2")
        #expect(try await preview.value("document.querySelectorAll('.heading-anchor').length") as? Int == 10)
    }

    @Test func nativeOutlineNavigationMovesAndFocusesHeadingAndReturnsToTop() async throws {
        let body = String(repeating: "正文内容，用来保留足够的阅读空间。\n\n", count: 40)
        let preview = try await render("# 开始\n\n\(body)\n## 中间章节\n\n\(body)\n## 最后章节\n\n\(body)")
        defer { preview.close() }
        preview.state.navigate(to: "中间章节")
        preview.coordinator.navigateIfNeeded()
        await preview.coordinator.navigationTask?.value
        try await waitForSection(preview, id: "中间章节")
        #expect(try await preview.value("window.scrollY > 1000") as? Bool == true)
        #expect(try await preview.value("Math.abs(document.getElementById('中间章节').getBoundingClientRect().top - 24) < 2") as? Bool == true)
        #expect(try await preview.value("document.activeElement.id") as? String == "中间章节")
        #expect(preview.coordinator.tab.markdownOffset > 1000)
        preview.state.navigate()
        preview.coordinator.navigateIfNeeded()
        await preview.coordinator.navigationTask?.value
        #expect(try await preview.value("window.scrollY") as? Double == 0)
        try await waitForSection(preview, id: "开始")
    }

    @Test func fragmentLinksAndHeadingPermalinksNavigateToDuplicateTitles() async throws {
        let body = String(repeating: "阅读段落。\n\n", count: 40)
        let preview = try await render("[跳到第二处](#重复-1)\n\n# 起点\n\n\(body)\n## 重复\n\n\(body)\n## 重复\n\n\(body)")
        defer { preview.close() }
        _ = try await preview.value("document.querySelector('main > p a').click()")
        try await waitForSection(preview, id: "重复-1")
        #expect(try await preview.value("document.activeElement.id") as? String == "重复-1")
        _ = try await preview.value("document.getElementById('重复').querySelector('.heading-anchor').click()")
        try await waitForSection(preview, id: "重复")
        #expect(try await preview.value("location.pathname") as? String == "/index.html")
    }

    @Test func scrollingUpdatesCurrentSectionAndThemeKeepsReadingPosition() async throws {
        let body = String(repeating: "保持阅读位置，不必来回寻找。\n\n", count: 50)
        let preview = try await render("# First\n\n\(body)\n## Second\n\n\(body)\n## Last\n\n\(body)")
        defer { preview.close() }
        _ = try await preview.value("window.scrollTo(0, document.getElementById('second').getBoundingClientRect().top + window.scrollY + 160)")
        try await waitForSection(preview, id: "second")
        let deadline = ContinuousClock.now + .seconds(2)
        while preview.coordinator.tab.markdownOffset < 1000 && ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(20)) }
        let offset = preview.coordinator.tab.markdownOffset
        #expect(offset > 1000)
        preview.coordinator.dark = true
        preview.coordinator.renderIfNeeded()
        await preview.coordinator.renderTask?.value
        try await waitForSection(preview, id: "second")
        let restored = try await preview.value("window.scrollY") as? Double ?? 0
        #expect(abs(restored - offset) < 2)
    }

    @Test func refreshingOutlineClearsOldHeadingsAndStaleCollapseState() async throws {
        let preview = try await render("# Old\n\n## Child\n\nText")
        defer { preview.close() }
        preview.coordinator.tab.markdownCollapsedHeadings = ["old"]
        preview.coordinator.source = "No headings here."
        preview.coordinator.renderIfNeeded()
        await preview.coordinator.renderTask?.value
        #expect(preview.state.headings.isEmpty)
        #expect(preview.state.activeHeadingID == nil)
        #expect(preview.coordinator.tab.markdownCollapsedHeadings.isEmpty)
        #expect(try await preview.value("window.luma.navigateToHeading('old')") as? Bool == false)
    }

    @Test func outlineHierarchyHandlesSkippedLevelsWithoutLosingParents() {
        let headings = [
            MarkdownHeading(id: "a", title: "A", level: 1),
            MarkdownHeading(id: "b", title: "B", level: 3),
            MarkdownHeading(id: "c", title: "C", level: 6),
            MarkdownHeading(id: "d", title: "D", level: 4),
            MarkdownHeading(id: "e", title: "E", level: 2)
        ]
        let items = MarkdownOutlineItem.make(headings)
        #expect(items.map(\.parents) == [[], ["a"], ["a", "b"], ["a", "b"], ["a"]])
        #expect(items.map(\.hasChildren) == [true, true, false, false, false])
        let collapsed: Set<String> = ["b"]
        #expect(items.filter { $0.parents.allSatisfy { !collapsed.contains($0) } }.map(\.id) == ["a", "b", "e"])
    }

    @Test func bundledNavigationSampleJumpsAfterImageAndDiagramLayoutAndResize() async throws {
        let folder = try #require(chineseWorkspace().samplesURL)
        let file = folder.appendingPathComponent("长文档导航.md")
        let preview = try await render(try String(contentsOf: file, encoding: .utf8), document: file, imageRoot: folder, width: 840)
        defer { preview.close() }
        #expect(preview.state.metrics["images"] == 1)
        #expect(preview.state.metrics["diagrams"] == 1)
        let records = preview.state.headings.filter { $0.title == "阅读记录" }
        #expect(records.map(\.id) == ["阅读记录", "阅读记录-1"])
        #expect(records.first?.summary.hasPrefix("这是第一处") == true)
        #expect(records.last?.summary.hasPrefix("这是第二处") == true)
        #expect(try await preview.value("document.querySelector('main').getBoundingClientRect().width") as? Double == 840)
        #expect(try await preview.value("getComputedStyle(document.documentElement).backgroundColor") as? String == "rgb(252, 252, 250)")
        preview.view.frame = NSRect(x: 0, y: 0, width: 430, height: 680)
        preview.state.navigate(to: "公式与图表之间")
        preview.coordinator.navigateIfNeeded()
        await preview.coordinator.navigationTask?.value
        try await waitForSection(preview, id: "公式与图表之间")
        #expect(try await preview.value("Math.abs(document.getElementById('公式与图表之间').getBoundingClientRect().top - 24) < 2") as? Bool == true)
        #expect(try await preview.value("document.querySelector('main').getBoundingClientRect().width === document.documentElement.clientWidth") as? Bool == true)
        #expect(try await preview.value("document.documentElement.scrollWidth <= document.documentElement.clientWidth") as? Bool == true)
        preview.coordinator.dark = true
        preview.coordinator.renderIfNeeded()
        await preview.coordinator.renderTask?.value
        try await waitForSection(preview, id: "公式与图表之间")
        #expect(try await preview.value("getComputedStyle(document.documentElement).backgroundColor") as? String == "rgb(26, 32, 43)")
        #expect(try await preview.value("document.documentElement.scrollWidth <= document.documentElement.clientWidth") as? Bool == true)
    }

    @Test func hugeOutlineIsBoundedAndRepeatedHeadingAnchorsStayUnique() async throws {
        let preview = try await render(String(repeating: "## Same\n\n", count: 2005))
        defer { preview.close() }
        #expect(preview.state.metrics["headings"] == 2005)
        #expect(preview.state.headings.count == 2000)
        #expect(preview.state.outlineTruncated)
        #expect(try await preview.value("new Set([...document.querySelectorAll('h2')].map(heading => heading.id)).size") as? Int == 2005)
        #expect(try await preview.value("document.querySelector('h2:last-of-type').id") as? String == "same-2004")
    }

    private func find(_ query: String, in preview: Preview) async throws -> MarkdownFindState {
        let search = preview.coordinator.tab.markdownFind
        search.setQuery(query)
        preview.coordinator.findIfNeeded()
        await preview.coordinator.findTask?.value
        try #require(search.error == nil, "\(search.error ?? "")")
        return search
    }

    @Test func previewFindMatchesAcrossInlineFormattingWithoutChangingContent() async throws {
        let preview = try await render("# 正文搜索\n\n本地**文件**阅读，与[阅读流程](#正文搜索)。\n\n本地文件 阅读。")
        defer { preview.close() }
        let before = try await preview.value("document.querySelector('main').innerHTML") as? String
        let search = try await find("本地文件阅读", in: preview)
        #expect(search.count == 1)
        #expect(search.current == 1)
        #expect(!preview.coordinator.tab.showSource)
        #expect(try await preview.value("document.querySelectorAll('.search-hit-current').length >= 2") as? Bool == true)
        #expect(try await preview.value("document.querySelector('main').innerHTML") as? String == before)
        _ = try await find("阅读流程", in: preview)
        #expect(search.count == 1)
        #expect(try await preview.value("(() => { const r = document.querySelector('.search-hit-current').getBoundingClientRect(); return !!document.elementFromPoint(r.left + r.width / 2, r.top + r.height / 2).closest('a'); })()") as? Bool == true)
    }

    @Test(arguments: [("hello", 2), ("中文", 2), ("🙂", 2), ("a+b? [x]", 1)])
    func previewFindTreatsUnicodeAndRegexCharactersAsLiteralText(query: String, count: Int) async throws {
        let preview = try await render("Hello HELLO 中文与中文 🙂🙂 `a+b? [x]`.")
        defer { preview.close() }
        let search = try await find(query, in: preview)
        #expect(search.count == count)
        #expect(search.current == 1)
    }

    @Test func previewFindCyclesBothWaysAndRevealsDistantResults() async throws {
        let body = String(repeating: "保持阅读空间。\n\n", count: 45)
        let preview = try await render("# 起点\n\nneedle\n\n\(body)\n## 远处\n\nneedle\n\n\(body)")
        defer { preview.close() }
        let search = try await find("needle", in: preview)
        #expect(search.count == 2)
        search.move(1); preview.coordinator.findIfNeeded(); await preview.coordinator.findTask?.value
        #expect(search.current == 2)
        #expect(try await preview.value("window.scrollY > 1000") as? Bool == true)
        #expect(try await preview.value("document.querySelector('.search-hit-current').dataset.match") as? String == "1")
        search.move(1); preview.coordinator.findIfNeeded(); await preview.coordinator.findTask?.value
        #expect(search.current == 1)
        search.move(-1); preview.coordinator.findIfNeeded(); await preview.coordinator.findTask?.value
        #expect(search.current == 2)
        #expect(!preview.coordinator.tab.showSource)
    }

    @Test func previewFindEmptyMissingAndCancelledQueriesClearHighlights() async throws {
        let preview = try await render("old old target")
        defer { preview.close() }
        let search = preview.coordinator.tab.markdownFind
        search.setQuery("old"); preview.coordinator.findIfNeeded()
        search.setQuery("target"); preview.coordinator.findIfNeeded()
        await preview.coordinator.findTask?.value
        #expect(search.count == 1)
        _ = try await find("不存在", in: preview)
        #expect(search.count == 0 && search.current == 0)
        #expect(search.status == "无匹配")
        #expect(!search.canMove)
        _ = try await find("old", in: preview)
        #expect(search.count == 2)
        search.clear(); preview.coordinator.findIfNeeded(); await preview.coordinator.findTask?.value
        #expect(search.count == 0 && search.current == 0)
        #expect(try await preview.value("document.querySelectorAll('.search-hit').length") as? Int == 0)
    }

    @Test func previewFindSearchesCodeMathAndDiagramLabelsWithoutHiddenDuplicates() async throws {
        let preview = try await render(#"""
        ```swift
        let needle = "value"
        ```

        $E=mc^2$

        ```mermaid
        flowchart LR
          %% SecretNeedle SecretNeedle
          A[VisibleLabel] --> B[End]
        ```
        """#)
        defer { preview.close() }
        let code = try await preview.value("document.querySelector('pre code').innerHTML") as? String
        let search = try await find("needle", in: preview)
        #expect(search.count == 1)
        #expect(try await preview.value("document.querySelector('pre code').innerHTML") as? String == code)
        _ = try await find("mc", in: preview)
        #expect(search.count == 1)
        _ = try await find("VisibleLabel", in: preview)
        #expect(search.count == 1)
        #expect(try await preview.value("document.querySelectorAll('.search-hit-current').length > 0") as? Bool == true)
        _ = try await find("SecretNeedle", in: preview)
        #expect(search.count == 0)
        _ = try await preview.value("document.querySelector('.diagram-source').open = true")
        let deadline = ContinuousClock.now + .seconds(2)
        while search.count != 2 && ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(20)) }
        #expect(search.count == 2 && search.current == 1)
        _ = try await find("复制源码", in: preview)
        #expect(search.count == 0)
    }

    @Test func previewFindKeepsCurrentResultAndPositionAcrossThemeAndRefresh() async throws {
        let body = String(repeating: "阅读中。\n\n", count: 50)
        let preview = try await render("needle\n\n\(body)\nneedle\n\n\(body)")
        defer { preview.close() }
        let search = try await find("needle", in: preview)
        search.move(1); preview.coordinator.findIfNeeded(); await preview.coordinator.findTask?.value
        let offset = preview.coordinator.tab.markdownOffset
        let light = try await preview.value("getComputedStyle(document.querySelector('.search-hit-current')).backgroundColor") as? String
        preview.coordinator.dark = true
        preview.coordinator.renderIfNeeded()
        await preview.coordinator.renderTask?.value
        await preview.coordinator.findTask?.value
        #expect(search.count == 2 && search.current == 2)
        #expect(try await preview.value("getComputedStyle(document.querySelector('.search-hit-current')).backgroundColor") as? String != light)
        #expect(abs((try await preview.value("window.scrollY") as? Double ?? 0) - offset) < 2)
        preview.coordinator.source += "\n\nneedle"
        preview.coordinator.renderIfNeeded()
        await preview.coordinator.renderTask?.value
        await preview.coordinator.findTask?.value
        #expect(search.count == 3 && search.current == 2)
    }

    @Test func previewFindRevealsHorizontallyScrolledCodeAndClipsHighlight() async throws {
        let preview = try await render("```text\n\(String(repeating: "x", count: 400)) TARGET\n```")
        defer { preview.close() }
        let search = try await find("TARGET", in: preview)
        #expect(search.count == 1)
        #expect(try await preview.value("document.querySelector('pre').scrollLeft > 1000") as? Bool == true)
        #expect(try await preview.value("(() => { const hit = document.querySelector('.search-hit-current').getBoundingClientRect(); const pre = document.querySelector('pre').getBoundingClientRect(); return hit.left >= pre.left - 1 && hit.right <= pre.right + 1; })()") as? Bool == true)
    }

    @Test func previewFindBoundsResultCountAndRecoversFromOversizedQuery() async throws {
        let preview = try await render(String(repeating: "needle ", count: 5002))
        defer { preview.close() }
        let search = try await find("needle", in: preview)
        #expect(search.count == 5000 && search.truncated)
        #expect(search.status.contains("+"))
        search.setQuery(String(repeating: "x", count: 1025)); preview.coordinator.findIfNeeded(); await preview.coordinator.findTask?.value
        #expect(search.error != nil)
        #expect(!search.canMove)
        _ = try await find("needle", in: preview)
        #expect(search.error == nil && search.canMove)
    }

    @Test func previewWidthChangesLiveWithoutRebuildingDocumentOrLosingSearch() async throws {
        let source = "# Width\n\nneedle\n\n" + String(repeating: "阅读空间中的文字可以随宽度重新排版。\n\n", count: 50) + "\n\nneedle"
        let preview = try await render(source, width: 680)
        defer { preview.close() }
        #expect(try await preview.value("document.querySelector('main').getBoundingClientRect().width") as? Double == 680)
        _ = try await preview.value("window.originalHeading = document.querySelector('h1'); true")
        let search = try await find("needle", in: preview)
        preview.coordinator.previewWidth = 0
        preview.coordinator.layoutIfNeeded()
        await preview.coordinator.layoutTask?.value
        #expect(try await preview.value("document.querySelector('main').getBoundingClientRect().width === document.documentElement.clientWidth") as? Bool == true)
        #expect(try await preview.value("document.querySelector('h1') === window.originalHeading") as? Bool == true)
        #expect(search.count == 2)
        #expect(try await preview.value("document.querySelectorAll('.search-hit-current').length > 0") as? Bool == true)
    }

    @Test(arguments: MarkdownFont.allCases)
    func typographyRendersWhileCodeAndMathKeepTheirFonts(font: MarkdownFont) async throws {
        let preview = try await render("# 排版\n\n正文 $x^2$\n\n```swift\nlet n = 2\n```\n\n| 表格 |\n| --- |\n| 内容 |",
                                       typography: .init(font: font, fontSize: 22, lineHeight: 2))
        defer { preview.close() }
        #expect(try await preview.value("getComputedStyle(document.querySelector('main')).fontSize") as? String == "22px")
        #expect(try await preview.value("getComputedStyle(document.querySelector('p')).lineHeight") as? String == "44px")
        let family = try #require(try await preview.value("getComputedStyle(document.querySelector('main')).fontFamily") as? String)
        switch font {
        case .system: #expect(family.contains("-apple-system"))
        case .songti: #expect(family.contains("Songti SC"))
        case .monospaced: #expect(family.contains("ui-monospace"))
        }
        #expect(try await preview.value("getComputedStyle(document.querySelector('pre code')).fontFamily.includes('monospace')") as? Bool == true)
        #expect(try await preview.value("getComputedStyle(document.querySelector('.katex')).fontFamily.includes('KaTeX')") as? Bool == true)
        #expect(try await preview.value("parseFloat(getComputedStyle(document.querySelector('h1')).fontSize) > 40") as? Bool == true)
        #expect(try await preview.value("parseFloat(getComputedStyle(document.querySelector('td')).fontSize) > 18") as? Bool == true)
    }

    @Test func liveTypographyPreservesParagraphSearchAndDocumentNodes() async throws {
        let paragraphs = (0..<40).map { "第\($0)段：" + String(repeating: "正文排版变化时保留阅读段落和搜索。", count: 12) }.joined(separator: "\n\n")
        let preview = try await render("# 即时排版\n\n" + paragraphs, width: 680)
        defer { preview.close() }
        let search = try await find("第20段", in: preview)
        _ = try await preview.value("(() => { window.originalHeading = document.querySelector('h1'); const p = document.querySelectorAll('main > p')[20]; window.scrollTo(0, p.getBoundingClientRect().top + window.scrollY + 10); return true; })()")
        await preview.coordinator.capturePosition()
        let saved = try #require(preview.coordinator.tab.markdownLocation)
        for typography in [MarkdownTypography(font: .songti, fontSize: 20, lineHeight: 2.1),
                           .init(font: .monospaced, fontSize: 28, lineHeight: 2.4),
                           .init(font: .system, fontSize: 12, lineHeight: 1.3)] {
            preview.coordinator.typography = typography
            preview.coordinator.layoutIfNeeded()
            await preview.coordinator.layoutTask?.value
            let location = try #require(preview.coordinator.tab.markdownLocation)
            #expect(location.blockKey == saved.blockKey)
            #expect(abs(location.blockProgress - saved.blockProgress) < 0.02)
            #expect(search.count == 1 && search.current == 1)
            #expect(try await preview.value("document.querySelector('h1') === window.originalHeading") as? Bool == true)
            #expect(try await preview.value("document.querySelectorAll('.search-hit-current').length > 0") as? Bool == true)
            #expect(try await preview.value("(() => { const range = document.createRange(); range.setStart(document.querySelectorAll('main > p')[20].firstChild, 0); range.setEnd(document.querySelectorAll('main > p')[20].firstChild, 4); const text = range.getBoundingClientRect(), hit = document.querySelector('.search-hit-current')?.getBoundingClientRect(); return !!hit && Math.abs(hit.top - text.top) < 2 && Math.abs(hit.width - text.width) < 2; })()") as? Bool == true)
            #expect(try await preview.value("parseFloat(getComputedStyle(document.querySelector('main')).fontSize)") as? Double == typography.fontSize)
        }
        // Rapid slider changes cancel earlier pending layouts; the latest value must win.
        for size in [16.0, 18, 24] {
            preview.coordinator.typography = .init(font: .songti, fontSize: size)
            preview.coordinator.layoutIfNeeded()
        }
        await preview.coordinator.layoutTask?.value
        #expect(try await preview.value("getComputedStyle(document.querySelector('main')).fontSize") as? String == "24px")
        #expect(try await preview.value("getComputedStyle(document.querySelector('main')).fontFamily.includes('Songti SC')") as? Bool == true)
    }

    @Test func savedTypographyAndReadingPositionApplyToReopenedPreview() async throws {
        let domain = "local.luma.typography-web-tests.\(UUID().uuidString)"
        let preferences = try #require(UserDefaults(suiteName: domain))
        defer { preferences.removePersistentDomain(forName: domain) }
        let workspace = chineseWorkspace(preferences: preferences)
        let paragraphs = (0..<40).map { "段落\($0)：" + String(repeating: "重开之后接着阅读。", count: 12) }.joined(separator: "\n\n")
        let source = "# 保存排版\n\n" + paragraphs
        let original = try await render(source)
        defer { original.close() }
        _ = try await original.value("(() => { const p = document.querySelectorAll('main > p')[20]; window.scrollTo(0, p.getBoundingClientRect().top + window.scrollY + 10); })()")
        await original.coordinator.capturePosition()
        let saved = try #require(original.coordinator.tab.markdownLocation)
        workspace.markdownFont = .monospaced
        workspace.markdownFontSize = 24
        workspace.markdownLineHeight = 2.2
        let restarted = chineseWorkspace(preferences: try #require(UserDefaults(suiteName: domain)))
        let reopened = try await render(source, typography: restarted.markdownTypography, location: saved)
        defer { reopened.close() }
        #expect(try await reopened.value("getComputedStyle(document.querySelector('main')).fontSize") as? String == "24px")
        let height = try #require(try await reopened.value("parseFloat(getComputedStyle(document.querySelector('main')).lineHeight)") as? Double)
        #expect(abs(height - 52.8) < 0.02)
        #expect(try await reopened.value("getComputedStyle(document.querySelector('main')).fontFamily.includes('ui-monospace')") as? Bool == true)
        await reopened.coordinator.capturePosition()
        #expect(reopened.coordinator.tab.markdownLocation?.blockKey == saved.blockKey)
    }

    @Test func previewRendersUnsavedSourceEditsIncludingMathAndTables() async throws {
        let preview = try await render("# Before\n\noriginal")
        defer { preview.close() }
        let tab = preview.coordinator.tab
        tab.draft = "# Before\n\noriginal"
        tab.savedText = tab.draft
        tab.edit("# After\n\n$x^2$\n\n| Name | Count |\n| --- | --- |\n| edited | 2 |")
        guard case .ready(.markdown(let source)) = tab.state else { Issue.record("Markdown draft did not update"); return }
        preview.coordinator.source = source
        preview.coordinator.renderIfNeeded()
        await preview.coordinator.renderTask?.value
        #expect(tab.isDirty && tab.savedText == "# Before\n\noriginal")
        #expect(preview.state.headings.first?.title == "After")
        #expect(preview.state.metrics["tables"] == 1)
        #expect(try await preview.value("document.querySelectorAll('.katex').length") as? Int == 1)
        #expect(try await preview.value("document.querySelector('td').textContent") as? String == "edited")
    }

    @Test func readingLocationRestoresSameParagraphAfterReopenWidthChangeAndInsertion() async throws {
        let paragraphs = (0..<40).map { "第\($0)段：" + String(repeating: "这是段内文字，宽度变化后仍应停在这段。", count: 8) }.joined(separator: "\n\n")
        let source = "# 阅读记忆\n\n" + paragraphs
        let original = try await render(source, width: 680)
        defer { original.close() }
        _ = try await original.value("(() => { const p = document.querySelectorAll('main > p')[20]; window.scrollTo(0, p.getBoundingClientRect().top + window.scrollY + 10); })()")
        await original.coordinator.capturePosition()
        let saved = try #require(original.coordinator.tab.markdownLocation)
        let updated = "# 阅读记忆\n\n新增前言，不应让原来的阅读段落丢失。\n\n" + paragraphs
        let reopened = try await render(updated, width: 0, location: saved)
        defer { reopened.close() }
        let values = try #require(try await reopened.value("window.luma.getReadingPosition()") as? [String: Any])
        let restored = try #require(MarkdownReadingLocation(message: values))
        #expect(restored.blockKey == saved.blockKey)
        #expect(abs(restored.blockProgress - saved.blockProgress) < 0.02)
        #expect(abs(restored.offset - saved.offset) > 20)
    }

    @Test func bookmarksCaptureActualPositionPersistAndNavigateAfterReopen() async throws {
        let domain = "local.luma.bookmark-web-tests.\(UUID().uuidString)"
        let preferences = try #require(UserDefaults(suiteName: domain))
        defer { preferences.removePersistentDomain(forName: domain) }
        let file = URL(fileURLWithPath: "/tmp/bookmark-\(UUID().uuidString).md")
        let history = MarkdownReadingHistory(preferences: preferences)
        let session = history.session(for: file)
        let body = String(repeating: "用段落记录阅读位置。\n\n", count: 45)
        let source = "# Start\n\n\(body)\n## Saved chapter\n\n\(body)"
        let original = try await render(source, document: file, session: session)
        defer { original.close() }
        original.state.navigate(to: "saved-chapter")
        original.coordinator.navigateIfNeeded()
        await original.coordinator.navigationTask?.value
        original.coordinator.tab.markdownBookmarkRequest += 1
        // Quit/close can happen before SwiftUI dispatches the pending bookmark action.
        await original.coordinator.tab.captureMarkdownPosition?()
        history.flush()
        let bookmark = try #require(session.bookmarks.first)
        #expect(bookmark.title.contains("Saved chapter"))
        #expect(bookmark.location.offset > 1000)
        let restoredHistory = MarkdownReadingHistory(preferences: preferences)
        let restoredSession = restoredHistory.session(for: file)
        let reopened = try await render(source, document: file, width: 1200, session: restoredSession)
        defer { reopened.close() }
        #expect(restoredSession.bookmarks.count == 1)
        #expect(try await reopened.value("window.scrollY > 1000") as? Bool == true)
        reopened.state.navigate()
        reopened.coordinator.navigateIfNeeded(); await reopened.coordinator.navigationTask?.value
        reopened.state.navigate(to: bookmark.location)
        reopened.coordinator.navigateIfNeeded(); await reopened.coordinator.navigationTask?.value
        let values = try #require(try await reopened.value("window.luma.getReadingPosition()") as? [String: Any])
        #expect(MarkdownReadingLocation(message: values)?.blockKey == bookmark.location.blockKey)
        restoredHistory.flush()
    }

    @Test func chapterBookmarkCanBeSavedWithoutScrollingAndRestoredLater() async throws {
        let domain = "local.luma.chapter-bookmark-tests.\(UUID().uuidString)"
        let preferences = try #require(UserDefaults(suiteName: domain))
        defer { preferences.removePersistentDomain(forName: domain) }
        let file = URL(fileURLWithPath: "/tmp/bookmark-\(UUID().uuidString).md")
        let history = MarkdownReadingHistory(preferences: preferences)
        let session = history.session(for: file)
        let body = String(repeating: "用段落记录阅读位置。\n\n", count: 45)
        let preview = try await render("# 开始\n\n\(body)\n## 目标章节\n\n\(body)", document: file, session: session)
        defer { preview.close() }
        let tab = preview.coordinator.tab
        tab.requestReadingBookmark(headingID: "目标章节")
        preview.coordinator.bookmarkIfNeeded()
        await preview.coordinator.bookmarkTask?.value
        #expect(try await preview.value("window.scrollY") as? Double == 0)
        let saved = try #require(MarkdownReadingHistory(preferences: preferences).session(for: file).bookmarks.first)
        #expect(saved.title == "目标章节")
        #expect(saved.location.headingID == "目标章节")
        preview.state.navigate(to: saved.location)
        preview.coordinator.navigateIfNeeded()
        await preview.coordinator.navigationTask?.value
        try await waitForSection(preview, id: "目标章节")
        #expect(try await preview.value("window.scrollY > 1000") as? Bool == true)
        session.removeBookmark(saved.id)
        #expect(MarkdownReadingHistory(preferences: preferences).session(for: file).bookmarks.isEmpty)
    }

    @Test func readingRestoreFallsBackWhenOriginalParagraphDisappears() async throws {
        let body = String(repeating: "在章节中保留阅读空间。\n\n", count: 40)
        let preview = try await render("# One\n\n\(body)\n## Two\n\n\(body)")
        defer { preview.close() }
        let fallback = MarkdownReadingLocation(offset: 2000, progress: 0.7, blockKey: "missing", blockProgress: 0.5, headingID: "two", headingProgress: 0.2)
        preview.state.navigate(to: fallback)
        preview.coordinator.navigateIfNeeded(); await preview.coordinator.navigationTask?.value
        let values = try #require(try await preview.value("window.luma.getReadingPosition()") as? [String: Any])
        #expect(values["headingID"] as? String == "two")
        let top = try await preview.value("document.getElementById('two').getBoundingClientRect().top + window.scrollY") as? Double ?? 0
        #expect((values["offset"] as? Double ?? 0) > top)
    }
}
