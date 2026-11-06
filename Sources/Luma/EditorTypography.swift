import Foundation

nonisolated enum EditorTypography {
    static let fontSizeRange = 10.0...28.0
    static let defaultFontSize = 13.0

    static func validFontSize(_ size: Double) -> Double {
        size.isFinite && fontSizeRange.contains(size) ? size : defaultFontSize
    }
}
