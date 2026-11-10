import Foundation

public enum InterfaceLanguage: String, CaseIterable, Sendable {
    case english = "en"
    case simplifiedChinese = "zh-Hans"

    public var nativeName: String { self == .simplifiedChinese ? "简体中文" : "English" }
    public var locale: Locale { Locale(identifier: rawValue) }
}

/// Keeps translated templates separate from user-supplied interpolation values.
public struct InterfaceMessage: ExpressibleByStringLiteral, ExpressibleByStringInterpolation, Sendable {
    public let key: String
    public let arguments: [String]
    public init(stringLiteral value: String) { key = value; arguments = [] }
    public init(stringInterpolation: StringInterpolation) {
        key = stringInterpolation.key; arguments = stringInterpolation.arguments
    }
    public struct StringInterpolation: StringInterpolationProtocol {
        var key = ""
        var arguments: [String] = []
        public init(literalCapacity: Int, interpolationCount: Int) { key.reserveCapacity(literalCapacity) }
        public mutating func appendLiteral(_ literal: String) { key += literal }
        public mutating func appendInterpolation<T>(_ value: T) {
            key += "{\(arguments.count)}"; arguments.append(String(describing: value))
        }
        public mutating func appendInterpolation(_ value: Double, specifier: String) {
            appendInterpolation(String(format: specifier, value))
        }
    }
    private static let placeholders = try! NSRegularExpression(pattern: #"\{(\d+)\}"#)
    public func rendered(template: String) -> String {
        guard !arguments.isEmpty else { return template }
        var output = "", cursor = template.startIndex
        for match in Self.placeholders.matches(in: template, range: NSRange(template.startIndex..., in: template)) {
            guard let range = Range(match.range, in: template), let numberRange = Range(match.range(at: 1), in: template),
                  let index = Int(template[numberRange]), arguments.indices.contains(index) else { continue }
            output += template[cursor..<range.lowerBound]
            output += arguments[index]
            cursor = range.upperBound
        }
        output += template[cursor...]
        return output
    }
}

public enum ReaderLocalization {
    // Readers report errors on worker actors as well as on the main actor.
    private final class Storage: @unchecked Sendable {
        let lock = NSLock()
        var language = InterfaceLanguage.english
    }
    private static let storage = Storage()
    private static let languageBundles = Dictionary(uniqueKeysWithValues: InterfaceLanguage.allCases.map {
        ($0, localizedBundle(for: $0, in: .module))
    })

    static func localizedBundle(for language: InterfaceLanguage, in bundle: Bundle) -> Bundle {
        // SwiftPM versions differ in whether they lowercase language directory names.
        guard let resources = bundle.resourceURL,
              let directories = try? FileManager.default.contentsOfDirectory(at: resources, includingPropertiesForKeys: nil),
              let directory = directories.first(where: {
                  $0.lastPathComponent.caseInsensitiveCompare("\(language.rawValue).lproj") == .orderedSame
              }), let localized = Bundle(url: directory) else { return bundle }
        return localized
    }

    public static var language: InterfaceLanguage {
        get { storage.lock.lock(); defer { storage.lock.unlock() }; return storage.language }
        set { storage.lock.lock(); defer { storage.lock.unlock() }; storage.language = newValue }
    }
    public static func text(_ message: InterfaceMessage, language: InterfaceLanguage? = nil) -> String {
        let language = language ?? self.language
        let bundle = languageBundles[language] ?? .module
        let template = bundle.localizedString(forKey: message.key, value: message.key, table: nil)
        return message.rendered(template: template)
    }
    public static func text(key: String, language: InterfaceLanguage? = nil) -> String {
        text(InterfaceMessage(stringLiteral: key), language: language)
    }
}

public func coreText(_ message: InterfaceMessage) -> String { ReaderLocalization.text(message) }
