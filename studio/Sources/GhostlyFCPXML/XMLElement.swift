import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif
import GhostlyCore

/// Lightweight XML tree used by the FCPXML engine. We own the serializer so
/// output is deterministic (stable attribute order) — essential for diffing
/// generated FCPXML in tests and version control.
public final class XML {
    public let name: String
    public private(set) var attributes: [(key: String, value: String)]
    public private(set) var children: [XML]
    public var text: String?

    public init(_ name: String, _ attributes: [(String, String)] = [], text: String? = nil) {
        self.name = name
        self.attributes = attributes.map { (key: $0.0, value: $0.1) }
        self.text = text
        self.children = []
    }

    @discardableResult
    public func attr(_ key: String, _ value: String?) -> XML {
        if let value { attributes.append((key: key, value: value)) }
        return self
    }

    @discardableResult
    public func child(_ element: XML) -> XML {
        children.append(element)
        return self
    }

    @discardableResult
    public func appendingChildren(_ elements: [XML]) -> XML {
        children.append(contentsOf: elements)
        return self
    }

    public subscript(attribute key: String) -> String? {
        attributes.first { $0.key == key }?.value
    }

    /// First child with the given element name.
    public func first(_ name: String) -> XML? {
        children.first { $0.name == name }
    }

    public func all(_ name: String) -> [XML] {
        children.filter { $0.name == name }
    }

    /// Depth-first search over descendants.
    public func descendants(_ name: String) -> [XML] {
        var out: [XML] = []
        for child in children {
            if child.name == name { out.append(child) }
            out.append(contentsOf: child.descendants(name))
        }
        return out
    }

    // MARK: Serialization

    public func serialized(indent: Int = 0) -> String {
        let pad = String(repeating: "    ", count: indent)
        let attrs = attributes.map { " \($0.key)=\"\(Self.escape($0.value, forAttribute: true))\"" }.joined()
        if children.isEmpty && text == nil {
            return "\(pad)<\(name)\(attrs)/>"
        }
        if children.isEmpty, let text {
            return "\(pad)<\(name)\(attrs)>\(Self.escape(text, forAttribute: false))</\(name)>"
        }
        var lines = ["\(pad)<\(name)\(attrs)>"]
        if let text { lines.append("\(pad)    \(Self.escape(text, forAttribute: false))") }
        lines.append(contentsOf: children.map { $0.serialized(indent: indent + 1) })
        lines.append("\(pad)</\(name)>")
        return lines.joined(separator: "\n")
    }

    static func escape(_ string: String, forAttribute: Bool) -> String {
        var out = string
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
        if forAttribute {
            out = out.replacingOccurrences(of: "\"", with: "&quot;")
        }
        return out
    }
}

// MARK: Parsing (SAX → DOM)

public enum XMLDocumentParser {
    public static func parse(_ data: Data) throws -> XML {
        let delegate = TreeBuilder()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        guard parser.parse(), let root = delegate.root else {
            let line = parser.parserError.map { " (\($0.localizedDescription))" } ?? ""
            throw StudioError.parseFailure(format: "XML", detail: "malformed document\(line)")
        }
        return root
    }

    public static func parse(_ string: String) throws -> XML {
        try parse(Data(string.utf8))
    }

    private final class TreeBuilder: NSObject, XMLParserDelegate {
        var root: XML?
        private var stack: [XML] = []
        private var pendingText = ""

        func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?,
                    qualifiedName: String?, attributes: [String: String]) {
            flushText()
            // Sort attribute keys so parsed trees serialize deterministically.
            let element = XML(name, attributes.sorted { $0.key < $1.key }.map { ($0.key, $0.value) })
            if let parent = stack.last {
                parent.child(element)
            } else {
                root = element
            }
            stack.append(element)
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            pendingText += string
        }

        func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?,
                    qualifiedName: String?) {
            flushText()
            stack.removeLast()
        }

        private func flushText() {
            let trimmed = pendingText.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty, let current = stack.last {
                current.text = (current.text.map { $0 + " " } ?? "") + trimmed
            }
            pendingText = ""
        }
    }
}
