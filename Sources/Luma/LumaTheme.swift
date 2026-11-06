import AppKit
import SwiftUI

/// Brand colors are explicit so macOS's system accent cannot turn navigation blue.
enum LumaTheme {
    static let nativeAccent = NSColor(name: "LumaAccent") { appearance in
        let dark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        return dark
            ? NSColor(srgbRed: 145 / 255, green: 199 / 255, blue: 175 / 255, alpha: 1)
            : NSColor(srgbRed: 56 / 255, green: 120 / 255, blue: 102 / 255, alpha: 1)
    }
    static let accent = Color(nsColor: nativeAccent)
    static let nativeSelection = nativeAccent.withAlphaComponent(0.24)

    static func apply(to textView: NSTextView) {
        textView.insertionPointColor = nativeAccent
        textView.selectedTextAttributes = [
            .backgroundColor: nativeSelection,
            .foregroundColor: NSColor.textColor
        ]
        textView.linkTextAttributes = [.foregroundColor: nativeAccent]
    }
}
