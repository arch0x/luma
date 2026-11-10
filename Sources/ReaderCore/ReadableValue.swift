import Foundation

/// Interprets a small, explicitly selected source value without changing the document.
public enum ReadableValue {
    public enum Kind: String, CaseIterable, Sendable {
        case color = "颜色", timestamp = "时间戳", bytes = "字节大小", string = "转义字符串"
    }
    public enum TimestampUnit: String, CaseIterable, Sendable {
        case seconds = "秒", milliseconds = "毫秒"
    }
    public struct RGBA: Equatable, Sendable {
        public let red: Double
        public let green: Double
        public let blue: Double
        public let alpha: Double
        public var hex: String {
            let values = [red, green, blue] + (alpha < 1 ? [alpha] : [])
            return "#" + values.map { String(format: "%02X", Int(($0 * 255).rounded())) }.joined()
        }
        public init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
            self.red = min(1, max(0, red)); self.green = min(1, max(0, green))
            self.blue = min(1, max(0, blue)); self.alpha = min(1, max(0, alpha))
        }
    }
    public static func unquoted(_ source: String) -> String {
        if source.count >= 2, source.first == "\"", source.last == "\"",
           let text = try? JSONDecoder().decode(String.self, from: Data(source.utf8)) { return text }
        if source.count >= 2, source.first == "'", source.last == "'" { return String(source.dropFirst().dropLast()) }
        return source
    }
    public static func encodeString(_ value: String) -> String {
        guard let data = try? JSONEncoder().encode(value), let result = String(data: data, encoding: .utf8) else { return "\"\"" }
        return result
    }
    public static func preservingQuotes(_ value: String, original: String) -> String {
        if original.first == "\"", original.last == "\"", original.count >= 2 { return encodeString(value) }
        if original.first == "'", original.last == "'", original.count >= 2 { return "'" + value + "'" }
        return value
    }
    public static func color(_ source: String) -> RGBA? {
        let value = unquoted(source)
        guard value.hasPrefix("#") else { return nil }
        var digits = String(value.dropFirst())
        guard [3, 4, 6, 8].contains(digits.count), digits.allSatisfy({ $0.isASCII && $0.isHexDigit }) else { return nil }
        if digits.count <= 4 { digits = digits.map { "\($0)\($0)" }.joined() }
        guard let number = UInt32(digits, radix: 16) else { return nil }
        let alpha = digits.count == 8
        let rgb = alpha ? number >> 8 : number
        return .init(red: Double((rgb >> 16) & 255) / 255,
                     green: Double((rgb >> 8) & 255) / 255,
                     blue: Double(rgb & 255) / 255,
                     alpha: alpha ? Double(number & 255) / 255 : 1)
    }
    public static func date(_ source: String, unit: TimestampUnit) -> Date? {
        guard let number = Double(unquoted(source)), number.isFinite else { return nil }
        let seconds = unit == .milliseconds ? number / 1000 : number
        // Keep formatting inside Gregorian years 0001...9999.
        guard (-62_135_596_800...253_402_300_799).contains(seconds) else { return nil }
        return Date(timeIntervalSince1970: seconds)
    }
    public static func byteCount(_ source: String) -> Double? {
        let text = unquoted(source).trimmingCharacters(in: .whitespaces)
        guard let range = text.range(of: #"^[+]?(?:\d+(?:\.\d*)?|\.\d+)\s*(?:[KMGT]i?B|B)?$"#, options: [.regularExpression, .caseInsensitive]) else { return nil }
        let value = String(text[range]).uppercased()
        let units: [(String, Double)] = [("TIB", pow(1024, 4)), ("GIB", pow(1024, 3)), ("MIB", pow(1024, 2)), ("KIB", 1024),
                                          ("TB", 1e12), ("GB", 1e9), ("MB", 1e6), ("KB", 1e3), ("B", 1)]
        let suffix = units.first { value.hasSuffix($0.0) }
        let numeric = suffix.map { String(value.dropLast($0.0.count)) } ?? value
        guard let number = Double(numeric.trimmingCharacters(in: .whitespaces)), number.isFinite else { return nil }
        let bytes = number * (suffix?.1 ?? 1)
        return bytes.isFinite && bytes <= 9_007_199_254_740_991 ? bytes : nil
    }
    public static func decodedString(_ source: String) -> String? {
        let json = source.hasPrefix("\"") ? source : "\"" + source + "\""
        return try? JSONDecoder().decode(String.self, from: Data(json.utf8))
    }
    public static func suggestedKind(_ source: String) -> Kind {
        if color(source) != nil { return .color }
        if Double(unquoted(source)) != nil { return .timestamp }
        if byteCount(source) != nil { return .bytes }
        return .string
    }
}
