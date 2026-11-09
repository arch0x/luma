import AppKit
import SwiftUI

/// A search activation is a request to become the window's actual first responder.
struct SearchTextField: NSViewRepresentable {
    @Binding var text: String
    let placeholder: String
    let accessibilityLabel: String
    let focusRequest: Int
    var focusOnAppear = true
    var onFocusChange: (Bool) -> Void = { _ in }
    var onSubmit: ((Bool) -> Void)?
    var onCancel: (() -> Void)?

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeNSView(context: Context) -> Field {
        let field = Field()
        field.isEditable = true
        field.isSelectable = true
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .systemFont(ofSize: 12)
        field.textColor = LumaTheme.nativeInk
        field.usesSingleLineMode = true
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        field.delegate = context.coordinator
        return field
    }

    func updateNSView(_ field: Field, context: Context) {
        context.coordinator.parent = self
        if field.stringValue != text { field.stringValue = text }
        field.placeholderString = placeholder
        field.setAccessibilityLabel(accessibilityLabel)
        field.activate(request: focusRequest, onAppear: focusOnAppear)
    }

    final class Field: NSTextField {
        private var lastRequest: Int?
        private var needsFocus = false
        private var scheduled = false

        func activate(request: Int, onAppear: Bool) {
            guard lastRequest != request else { return }
            let initial = lastRequest == nil
            lastRequest = request
            if !initial || onAppear || request > 0 {
                needsFocus = true
                scheduleFocus()
            }
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            scheduleFocus()
        }

        override func layout() {
            super.layout()
            scheduleFocus()
        }

        private func scheduleFocus() {
            guard needsFocus, !scheduled else { return }
            scheduled = true
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                scheduled = false
                guard needsFocus, let window, !isHiddenOrHasHiddenAncestor,
                      bounds.width > 0, bounds.height > 0, window.makeFirstResponder(self),
                      let editor = currentEditor() as? NSTextView else { return }
                editor.setSelectedRange(NSRange(location: (stringValue as NSString).length, length: 0))
                needsFocus = false
            }
        }
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: SearchTextField
        init(parent: SearchTextField) { self.parent = parent }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            parent.text = field.stringValue
        }
        func controlTextDidBeginEditing(_ notification: Notification) {
            if let field = notification.object as? NSTextField,
               let editor = field.currentEditor() as? NSTextView { LumaTheme.apply(to: editor) }
            parent.onFocusChange(true)
        }
        func controlTextDidEndEditing(_ notification: Notification) { parent.onFocusChange(false) }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.insertNewline(_:)), let submit = parent.onSubmit {
                submit(NSApp.currentEvent?.modifierFlags.contains(.shift) ?? false)
                return true
            }
            if commandSelector == #selector(NSResponder.cancelOperation(_:)), let cancel = parent.onCancel {
                cancel()
                return true
            }
            return false
        }
    }
}
