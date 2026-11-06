import Foundation

enum MarkdownFont: String, CaseIterable, Identifiable {
    case system, songti, monospaced

    var id: Self { self }
    var title: String {
        switch self {
        case .system: "系统字体"
        case .songti: "宋体"
        case .monospaced: "等宽字体"
        }
    }
}

struct MarkdownTypography: Equatable {
    static let fontSizeRange = 12.0...28.0
    static let lineHeightRange = 1.3...2.4
    let font: MarkdownFont
    let fontSize: Double
    let lineHeight: Double

    init(font: MarkdownFont = .system, fontSize: Double = 15, lineHeight: Double = 1.85) {
        self.font = font
        self.fontSize = fontSize.isFinite && Self.fontSizeRange.contains(fontSize) ? fontSize : 15
        self.lineHeight = lineHeight.isFinite && Self.lineHeightRange.contains(lineHeight) ? lineHeight : 1.85
    }

    var javascriptValue: [String: Any] {
        ["font": font.rawValue, "fontSize": fontSize, "lineHeight": lineHeight]
    }
}
