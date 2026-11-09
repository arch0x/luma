import SwiftUI
import AppKit

final class SourceTextView: NSTextView {
    private let documentUndoManager = UndoManager()
    override var undoManager: UndoManager? { documentUndoManager }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        LumaTheme.apply(to: self)
    }
}

/// Kept by the tab so selection, scroll position and native undo survive view switches.
final class SourceEditor: NSObject, NSTextViewDelegate {
    let scrollView = NSScrollView()
    let textView = SourceTextView()
    private weak var tab: DocumentTab?
    private var replacing = false
    private var query = ""
    private var lastFindRequest = 0
    private var match: NSRange?

    init(tab: DocumentTab) {
        self.tab = tab
        super.init()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.horizontalScrollElasticity = .none
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = true
        scrollView.backgroundColor = LumaTheme.nativePaper
        textView.isEditable = true
        textView.isSelectable = true
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.minSize = .zero
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.lineBreakMode = .byCharWrapping
        textView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainerInset = NSSize(width: 26, height: 26)
        let font = NSFont.monospacedSystemFont(ofSize: EditorTypography.defaultFontSize, weight: .regular)
        textView.font = font
        textView.textColor = LumaTheme.nativeInk
        textView.backgroundColor = LumaTheme.nativePaper
        LumaTheme.apply(to: textView)
        textView.isAutomaticLinkDetectionEnabled = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.usesFindBar = false
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 5
        paragraph.lineBreakMode = .byCharWrapping
        textView.defaultParagraphStyle = paragraph
        textView.typingAttributes = [.font: font,
                                     .foregroundColor: LumaTheme.nativeInk, .paragraphStyle: paragraph]
        textView.delegate = self
        scrollView.documentView = textView
        replaceFromDisk(tab.draft ?? "")
        scrollView.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(self, selector: #selector(didScroll), name: NSView.boundsDidChangeNotification, object: scrollView.contentView)
        NotificationCenter.default.addObserver(self, selector: #selector(undoOrRedoFinished), name: .NSUndoManagerDidUndoChange, object: textView.undoManager)
        NotificationCenter.default.addObserver(self, selector: #selector(undoOrRedoFinished), name: .NSUndoManagerDidRedoChange, object: textView.undoManager)
    }

    func setFontSize(_ value: Double) {
        let size = CGFloat(EditorTypography.validFontSize(value))
        guard textView.font?.pointSize != size else { return }
        let selection = textView.selectedRange()
        let font = NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
        textView.font = font
        var attributes = textView.typingAttributes
        attributes[.font] = font
        textView.typingAttributes = attributes
        if textView.selectedRange() != selection { textView.setSelectedRange(selection) }
    }

    func replaceFromDisk(_ text: String) {
        replacing = true
        defer { replacing = false }
        let selected = textView.selectedRange()
        textView.string = text
        textView.setSelectedRange(NSRange(location: min(selected.location, (text as NSString).length), length: 0))
        textView.undoManager?.removeAllActions()
        match = nil
    }

    func synchronize(_ text: String) {
        // SwiftUI can deliver an older view snapshot while switching modes.
        // The tab owns the latest draft; never replace it with that stale snapshot.
        let current = tab?.draft ?? text
        if textView.string != current { replaceFromDisk(current) }
        textView.isEditable = tab?.isLoading == false
    }

    func textDidChange(_ notification: Notification) {
        guard !replacing else { return }
        match = nil
        tab?.edit(textView.string)
    }

    @objc private func didScroll() { tab?.textOffset = scrollView.contentView.bounds.origin.y }

    @objc private func undoOrRedoFinished() {
        // UndoManager can update text storage without the usual typing delegate callback.
        tab?.edit(textView.string)
    }

    func updateFind() {
        guard let tab, lastFindRequest != tab.findRequest || query != tab.sourceQuery else { return }
        let changed = query != tab.sourceQuery
        lastFindRequest = tab.findRequest
        query = tab.sourceQuery
        guard !query.isEmpty else { match = nil; return }
        let text = textView.string as NSString
        let start = min(changed ? 0 : (match.map(NSMaxRange) ?? 0), text.length)
        let next = text.range(of: query, options: .caseInsensitive, range: NSRange(location: start, length: text.length - start))
        let found = next.location != NSNotFound ? next : text.range(of: query, options: .caseInsensitive)
        if found.location != NSNotFound {
            match = found
            textView.setSelectedRange(found)
            textView.scrollRangeToVisible(found)
        }
    }
}

struct SourceView: NSViewRepresentable {
    let text: String
    let tab: DocumentTab
    var fontSize: Double = EditorTypography.defaultFontSize

    func makeNSView(context: Context) -> NSScrollView { tab.sourceEditor().scrollView }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        let editor = tab.sourceEditor()
        editor.synchronize(text)
        editor.setFontSize(fontSize)
        editor.updateFind()
    }
}
