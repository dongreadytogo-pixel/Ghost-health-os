import Foundation
#if canImport(Glibc)
import Glibc
#elseif canImport(Darwin)
import Darwin
#endif
import GhostlyCore

/// A tool exposed over MCP: JSON schema in, structured content out.
public protocol MCPTool: Sendable {
    var name: String { get }
    var description: String { get }
    /// JSON Schema describing the tool's arguments.
    var inputSchema: JSONValue { get }
    func call(arguments: JSONValue) async throws -> JSONValue
}

/// Model Context Protocol server core: dispatches JSON-RPC messages to the
/// registered tools. Transport-agnostic — `StdioTransport` runs it over
/// stdin/stdout; tests call `handle(_:)` directly.
public actor MCPServer {
    public static let protocolVersion = "2024-11-05"

    public let serverName: String
    public let serverVersion: String
    private var tools: [String: any MCPTool] = [:]
    private var toolOrder: [String] = []
    private var initialized = false
    private let logger: GhostlyCore.Logger

    public init(serverName: String = "ghostly-studio",
                serverVersion: String = "1.0.0",
                logger: GhostlyCore.Logger = .init(subsystem: "MCPServer")) {
        self.serverName = serverName
        self.serverVersion = serverVersion
        self.logger = logger
    }

    public func register(_ tool: any MCPTool) {
        if tools[tool.name] == nil { toolOrder.append(tool.name) }
        tools[tool.name] = tool
    }

    public var toolNames: [String] { toolOrder }

    /// Handles one raw JSON-RPC message. Returns nil for notifications.
    public func handle(_ data: Data) async -> JSONValue? {
        let json: JSONValue
        do {
            json = try JSONValue(from: data)
        } catch {
            return JSONRPCResponse.failure(id: .null, code: JSONRPCError.parseError,
                                           message: "could not parse JSON")
        }
        guard let request = JSONRPCRequest(json: json) else {
            return JSONRPCResponse.failure(id: json["id"] ?? .null,
                                           code: JSONRPCError.invalidRequest,
                                           message: "not a JSON-RPC 2.0 request")
        }
        return await dispatch(request)
    }

    private func dispatch(_ request: JSONRPCRequest) async -> JSONValue? {
        switch request.method {
        case "initialize":
            initialized = true
            let result: JSONValue = .object([
                "protocolVersion": .string(Self.protocolVersion),
                "capabilities": .object(["tools": .object([:])]),
                "serverInfo": .object([
                    "name": .string(serverName),
                    "version": .string(serverVersion),
                ]),
            ])
            return request.id.map { JSONRPCResponse.success(id: $0, result: result) }

        case "notifications/initialized", "notifications/cancelled":
            return nil

        case "ping":
            return request.id.map { JSONRPCResponse.success(id: $0, result: .object([:])) }

        case "tools/list":
            let list = toolOrder.compactMap { tools[$0] }.map { tool -> JSONValue in
                .object([
                    "name": .string(tool.name),
                    "description": .string(tool.description),
                    "inputSchema": tool.inputSchema,
                ])
            }
            return request.id.map {
                JSONRPCResponse.success(id: $0, result: .object(["tools": .array(list)]))
            }

        case "tools/call":
            guard let id = request.id else { return nil }
            guard let name = request.params["name"]?.stringValue else {
                return JSONRPCResponse.failure(id: id, code: JSONRPCError.invalidParams,
                                               message: "missing tool name")
            }
            guard let tool = tools[name] else {
                return JSONRPCResponse.failure(id: id, code: JSONRPCError.methodNotFound,
                                               message: "unknown tool '\(name)'")
            }
            let arguments = request.params["arguments"] ?? .object([:])
            do {
                let content = try await tool.call(arguments: arguments)
                let text: String
                if case .string(let s) = content {
                    text = s
                } else {
                    text = String(data: try content.encoded(), encoding: .utf8) ?? "{}"
                }
                return JSONRPCResponse.success(id: id, result: .object([
                    "content": .array([.object(["type": "text", "text": .string(text)])]),
                    "isError": .bool(false),
                ]))
            } catch {
                // Tool failures are results, not protocol errors (MCP spec).
                let message = (error as? StudioError)?.errorDescription ?? error.localizedDescription
                logger.warning("tool \(name) failed: \(message)")
                return JSONRPCResponse.success(id: id, result: .object([
                    "content": .array([.object(["type": "text", "text": .string(message)])]),
                    "isError": .bool(true),
                ]))
            }

        default:
            guard let id = request.id else { return nil }
            return JSONRPCResponse.failure(id: id, code: JSONRPCError.methodNotFound,
                                           message: "method '\(request.method)' not supported")
        }
    }
}

/// Newline-delimited JSON-RPC over stdin/stdout — the MCP stdio transport.
public struct StdioTransport {
    private let server: MCPServer

    public init(server: MCPServer) {
        self.server = server
    }

    /// Blocks reading stdin until EOF. All logging must go to stderr; stdout
    /// carries protocol frames only.
    public func run() async {
        while let line = readLine(strippingNewline: true) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            if let response = await server.handle(Data(trimmed.utf8)),
               let data = try? response.encoded(),
               let text = String(data: data, encoding: .utf8) {
                print(text)
                fflush(stdout) // stdout may be pipe-buffered; the client is waiting
            }
        }
    }
}
