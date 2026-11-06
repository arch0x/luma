import Foundation
import CoreFoundation

public struct JSONNode: Identifiable, Sendable {
    public let id: String
    public let key: String
    public let value: String
    public let children: [JSONNode]?
    public let isString: Bool

    public static func parse(_ text: String) throws -> JSONNode {
        let object = try JSONSerialization.jsonObject(with: Data(text.utf8), options: [.fragmentsAllowed])
        return try make(object, key: "root", path: "", depth: 0)
    }

    private static func make(_ object: Any, key: String, path: String, depth: Int) throws -> JSONNode {
        guard depth < 128 else {
            throw NSError(domain: "JSON", code: 1, userInfo: [NSLocalizedDescriptionKey: "JSON 嵌套超过 128 层，请使用源码视图。"])
        }
        if let dictionary = object as? [String: Any] {
            let children = try dictionary.sorted { $0.key < $1.key }.map { name, item in
                let escaped = name.replacingOccurrences(of: "~", with: "~0").replacingOccurrences(of: "/", with: "~1")
                return try make(item, key: name, path: path + "/" + escaped, depth: depth + 1)
            }
            return JSONNode(id: path, key: key, value: "{ \(children.count) 项 }", children: children, isString: false)
        }
        if let array = object as? [Any] {
            let children = try array.enumerated().map { index, item in
                try make(item, key: "[\(index)]", path: path + "/\(index)", depth: depth + 1)
            }
            return JSONNode(id: path, key: key, value: "[ \(children.count) 项 ]", children: children, isString: false)
        }
        let value: String
        let isString: Bool
        if let number = object as? NSNumber {
            value = CFGetTypeID(number) == CFBooleanGetTypeID() ? (number.boolValue ? "true" : "false") : number.stringValue
            isString = false
        } else if let string = object as? String {
            value = "\"\(string)\""
            isString = true
        } else {
            value = "null"
            isString = false
        }
        return JSONNode(id: path, key: key, value: value, children: nil, isString: isString)
    }
}
