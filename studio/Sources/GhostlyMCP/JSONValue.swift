import Foundation
import GhostlyCore

/// A fully-typed representation of arbitrary JSON — the payload currency of
/// the MCP server (Codable, Sendable, and pattern-matchable, unlike `Any`).
public enum JSONValue: Sendable, Equatable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    // MARK: Convenience accessors

    public var stringValue: String? {
        if case .string(let s) = self { return s }
        return nil
    }

    public var numberValue: Double? {
        if case .number(let n) = self { return n }
        return nil
    }

    public var intValue: Int? {
        numberValue.flatMap { $0 == $0.rounded() ? Int($0) : nil }
    }

    public var boolValue: Bool? {
        if case .bool(let b) = self { return b }
        return nil
    }

    public var arrayValue: [JSONValue]? {
        if case .array(let a) = self { return a }
        return nil
    }

    public var objectValue: [String: JSONValue]? {
        if case .object(let o) = self { return o }
        return nil
    }

    public subscript(key: String) -> JSONValue? {
        objectValue?[key]
    }

    // MARK: Codable bridging

    public init(from data: Data) throws {
        guard !data.isEmpty else { throw StudioError.parseFailure(format: "JSON", detail: "empty input") }
        let object = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        self = JSONValue(any: object)
    }

    public init(any: Any) {
        switch any {
        case is NSNull: self = .null
        case let number as NSNumber:
            // Distinguish booleans from numbers (both are NSNumber).
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                self = .bool(number.boolValue)
            } else {
                self = .number(number.doubleValue)
            }
        case let string as String: self = .string(string)
        case let array as [Any]: self = .array(array.map(JSONValue.init(any:)))
        case let dict as [String: Any]: self = .object(dict.mapValues(JSONValue.init(any:)))
        default: self = .null
        }
    }

    public var anyValue: Any {
        switch self {
        case .null: return NSNull()
        case .bool(let b): return b
        case .number(let n): return n == n.rounded() && abs(n) < 1e15 ? Int(n) as Any : n
        case .string(let s): return s
        case .array(let a): return a.map(\.anyValue)
        case .object(let o): return o.mapValues(\.anyValue)
        }
    }

    public func encoded() throws -> Data {
        try JSONSerialization.data(withJSONObject: anyValue,
                                   options: [.fragmentsAllowed, .sortedKeys])
    }
}

extension JSONValue: ExpressibleByStringLiteral, ExpressibleByIntegerLiteral,
                     ExpressibleByFloatLiteral, ExpressibleByBooleanLiteral,
                     ExpressibleByArrayLiteral, ExpressibleByDictionaryLiteral,
                     ExpressibleByNilLiteral {
    public init(stringLiteral value: String) { self = .string(value) }
    public init(integerLiteral value: Int) { self = .number(Double(value)) }
    public init(floatLiteral value: Double) { self = .number(value) }
    public init(booleanLiteral value: Bool) { self = .bool(value) }
    public init(arrayLiteral elements: JSONValue...) { self = .array(elements) }
    public init(dictionaryLiteral elements: (String, JSONValue)...) {
        self = .object(Dictionary(uniqueKeysWithValues: elements))
    }
    public init(nilLiteral: ()) { self = .null }
}

// MARK: JSON-RPC 2.0

public struct JSONRPCRequest: Sendable {
    public let id: JSONValue?   // absent for notifications
    public let method: String
    public let params: JSONValue

    public init?(json: JSONValue) {
        guard json["jsonrpc"]?.stringValue == "2.0",
              let method = json["method"]?.stringValue else { return nil }
        self.id = json["id"]
        self.method = method
        self.params = json["params"] ?? .object([:])
    }

    public var isNotification: Bool { id == nil }
}

public enum JSONRPCError {
    public static let parseError = -32700
    public static let invalidRequest = -32600
    public static let methodNotFound = -32601
    public static let invalidParams = -32602
    public static let internalError = -32603
}

public enum JSONRPCResponse {
    public static func success(id: JSONValue, result: JSONValue) -> JSONValue {
        .object(["jsonrpc": "2.0", "id": id, "result": result])
    }

    public static func failure(id: JSONValue, code: Int, message: String) -> JSONValue {
        .object(["jsonrpc": "2.0", "id": id,
                 "error": .object(["code": .number(Double(code)), "message": .string(message)])])
    }
}
