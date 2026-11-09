import AppKit
import SwiftUI

enum LumaTheme {
    // Shared roles match preview.css. Document status and search have their own colors.
    static let nativeAccent = adaptive(light: 0x3A6095, dark: 0xA6C5F2)
    static let nativePaper = adaptive(light: 0xFCFCFA, dark: 0x1A202B)
    static let nativeInk = adaptive(light: 0x222B3A, dark: 0xE2E9F3)
    static let accent = Color(nsColor: nativeAccent)
    static let paper = Color(nsColor: nativePaper)
    static let ink = Color(nsColor: nativeInk)
    static let chrome = Color(nsColor: adaptive(light: 0xF1F4F8, dark: 0x151A23))
    static let muted = Color(nsColor: adaptive(light: 0x556378, dark: 0xA8B4C6))
    static let line = Color(nsColor: adaptive(light: 0xDCE3EC, dark: 0x313C4E))
    static let fieldBorder = Color(nsColor: adaptive(light: 0x7C8A9D, dark: 0x6B7B91))
    static let control = Color(nsColor: adaptive(light: 0xFFFFFF, dark: 0x202838))
    static let controlBorder = Color(nsColor: adaptive(light: 0xCFD8E5, dark: 0x404E62))
    static let hover = Color(nsColor: adaptive(light: 0xE9EEF5, dark: 0x263244))
    static let selected = Color(nsColor: adaptive(light: 0xE1EAF7, dark: 0x283B57))
    static let sectionMark = Color(nsColor: adaptive(light: 0x8792A3, dark: 0x6B7B91))
    static let currentSectionMark = Color(nsColor: adaptive(light: 0x303B4E, dark: 0xF4F6FA))
    static let onAccent = Color(nsColor: adaptive(light: 0xFFFFFF, dark: 0x172B49))
    static let warning = Color(nsColor: adaptive(light: 0x80551E, dark: 0xF2CA8E))
    static let warningSurface = Color(nsColor: adaptive(light: 0xFBF1DF, dark: 0x342A1D))
    static let danger = Color(nsColor: adaptive(light: 0xA12D40, dark: 0xFFACB8))
    static let nativeSelection = nativeAccent.withAlphaComponent(0.24)
    static let controlRadius: CGFloat = 7
    static let groupRadius: CGFloat = 10

    private static func adaptive(light: UInt32, dark: UInt32) -> NSColor {
        NSColor(name: nil) { appearance in
            let hex = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed: CGFloat((hex >> 16) & 255) / 255,
                           green: CGFloat((hex >> 8) & 255) / 255,
                           blue: CGFloat(hex & 255) / 255, alpha: 1)
        }
    }

    static func apply(to textView: NSTextView) {
        textView.insertionPointColor = nativeAccent
        textView.selectedTextAttributes = [
            .backgroundColor: nativeSelection,
            .foregroundColor: NSColor.textColor
        ]
        textView.linkTextAttributes = [.foregroundColor: nativeAccent]
    }
}

struct LumaRule: View {
    var axis: Axis = .horizontal
    var body: some View {
        Rectangle().fill(LumaTheme.line)
            .frame(width: axis == .vertical ? 1 : nil, height: axis == .horizontal ? 1 : nil)
            .accessibilityHidden(true)
    }
}

struct LumaButtonStyle: ButtonStyle {
    enum Emphasis { case primary, secondary, quiet }
    var emphasis: Emphasis = .quiet
    var selected = false
    @Environment(\.isEnabled) private var enabled
    @Environment(\.isFocused) private var focused
    @ViewState private var hovered = false

    func makeBody(configuration: Configuration) -> some View {
        let fill: Color = switch emphasis {
        case .primary: LumaTheme.accent
        case .secondary: hovered ? LumaTheme.hover : LumaTheme.control
        case .quiet: selected ? LumaTheme.selected : hovered ? LumaTheme.hover : .clear
        }
        configuration.label
            .font(.system(size: 12, weight: emphasis == .primary || selected ? .semibold : .medium))
            .foregroundStyle(emphasis == .primary ? LumaTheme.onAccent : selected ? LumaTheme.accent : LumaTheme.ink)
            .padding(.horizontal, emphasis == .quiet ? 7 : 12)
            .frame(minWidth: 28, minHeight: emphasis == .quiet ? 28 : 32)
            .background(fill, in: RoundedRectangle(cornerRadius: LumaTheme.controlRadius))
            .overlay {
                RoundedRectangle(cornerRadius: LumaTheme.controlRadius)
                    .strokeBorder(emphasis == .secondary ? LumaTheme.controlBorder : .clear)
                    .allowsHitTesting(false)
            }
            .lumaFocusRing(focused && enabled)
            .contentShape(Rectangle())
            .opacity(enabled ? (configuration.isPressed ? 0.72 : 1) : 0.5)
            .onHover { hovered = $0 && enabled }
    }
}

extension View {
    func lumaFocusRing(_ focused: Bool) -> some View {
        overlay {
            if focused {
                RoundedRectangle(cornerRadius: LumaTheme.controlRadius + 2)
                    .strokeBorder(LumaTheme.accent, lineWidth: 2)
                    .padding(-2)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
    }

    func lumaField(focused: Bool) -> some View {
        padding(.horizontal, 10)
            .frame(minHeight: 33)
            .background(LumaTheme.control, in: RoundedRectangle(cornerRadius: LumaTheme.controlRadius))
            .overlay {
                RoundedRectangle(cornerRadius: LumaTheme.controlRadius)
                    .strokeBorder(focused ? LumaTheme.accent : LumaTheme.fieldBorder)
                    .allowsHitTesting(false)
            }
            .lumaFocusRing(focused)
    }
}
