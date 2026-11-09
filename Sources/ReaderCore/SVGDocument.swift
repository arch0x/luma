import Foundation

public enum SVGDocument {
    public static let previewLimit = 1_024 * 1_024

    public static func validate(_ source: String) throws {
        let data = Data(source.utf8)
        guard data.count <= previewLimit else { throw SVGError.tooLarge }
        guard source.range(of: "<!DOCTYPE", options: .caseInsensitive) == nil,
              source.range(of: "<!ENTITY", options: .caseInsensitive) == nil else { throw SVGError.externalDeclaration }
        let parser = XMLParser(data: data)
        let root = SVGRoot()
        parser.delegate = root
        parser.shouldProcessNamespaces = true
        parser.shouldResolveExternalEntities = false
        parser.externalEntityResolvingPolicy = .never
        guard parser.parse(), root.isSVG else { throw SVGError.invalid }
    }

    public enum SVGError: LocalizedError {
        case invalid, externalDeclaration, tooLarge
        public var errorDescription: String? {
            switch self {
            case .invalid: "SVG 格式不完整，或缺少 SVG 根元素与命名空间。可以继续编辑源码。"
            case .externalDeclaration: "SVG 预览不支持 DOCTYPE 或实体声明。可以查看和编辑源码。"
            case .tooLarge: "SVG 超过 1 MB 预览上限。可以查看和编辑源码。"
            }
        }
    }
}

private final class SVGRoot: NSObject, XMLParserDelegate {
    private var foundRoot = false
    var isSVG = false

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?, attributes attributeDict: [String: String]) {
        guard !foundRoot else { return }
        foundRoot = true
        isSVG = elementName == "svg" && namespaceURI == "http://www.w3.org/2000/svg"
    }
}
