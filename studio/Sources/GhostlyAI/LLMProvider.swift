import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import GhostlyCore

/// A chat exchange with any language model.
public struct ChatMessage: Hashable, Sendable, Codable {
    public enum ChatRole: String, Sendable, Codable {
        case system, user, assistant
    }

    public var role: ChatRole
    public var content: String

    public init(role: ChatRole, content: String) {
        self.role = role
        self.content = content
    }

    public static func system(_ content: String) -> ChatMessage { .init(role: .system, content: content) }
    public static func user(_ content: String) -> ChatMessage { .init(role: .user, content: content) }
    public static func assistant(_ content: String) -> ChatMessage { .init(role: .assistant, content: content) }
}

public struct LLMRequest: Sendable {
    public var messages: [ChatMessage]
    public var maxTokens: Int
    public var temperature: Double
    /// Overrides the provider's default model when set.
    public var model: String?

    public init(messages: [ChatMessage], maxTokens: Int = 1024,
                temperature: Double = 0.3, model: String? = nil) {
        self.messages = messages
        self.maxTokens = maxTokens
        self.temperature = min(max(temperature, 0), 2)
        self.model = model
    }
}

public struct LLMResponse: Sendable, Equatable {
    public var text: String
    public var model: String
    public var inputTokens: Int?
    public var outputTokens: Int?

    public init(text: String, model: String, inputTokens: Int? = nil, outputTokens: Int? = nil) {
        self.text = text
        self.model = model
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
    }
}

/// What a provider is good at — the router's routing key.
public enum AICapability: String, Sendable, Codable, CaseIterable {
    case editing        // edit-plan generation, creative direction
    case summarization
    case vision
    case codegen        // FCPXML/Motion template generation
    case fast           // low-latency small tasks
    case local          // runs without network/cloud
}

public protocol LLMProvider: Sendable {
    var name: String { get }
    var capabilities: Set<AICapability> { get }
    func complete(_ request: LLMRequest) async throws -> LLMResponse
}

// MARK: HTTP transport (injectable so adapters are testable without network)

public struct HTTPRequest: Sendable {
    public var url: URL
    public var method: String
    public var headers: [String: String]
    public var body: Data?

    public init(url: URL, method: String = "POST", headers: [String: String] = [:], body: Data? = nil) {
        self.url = url
        self.method = method
        self.headers = headers
        self.body = body
    }
}

public struct HTTPResponse: Sendable {
    public var status: Int
    public var body: Data

    public init(status: Int, body: Data) {
        self.status = status
        self.body = body
    }
}

public protocol HTTPTransport: Sendable {
    func send(_ request: HTTPRequest) async throws -> HTTPResponse
}

public struct URLSessionTransport: HTTPTransport {
    private let session: URLSession

    public init(timeout: TimeInterval = 120) {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = timeout
        self.session = URLSession(configuration: config)
    }

    public func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        var urlRequest = URLRequest(url: request.url)
        urlRequest.httpMethod = request.method
        urlRequest.httpBody = request.body
        for (key, value) in request.headers {
            urlRequest.setValue(value, forHTTPHeaderField: key)
        }
        let (data, response): (Data, URLResponse)
        #if canImport(FoundationNetworking)
        // swift-corelibs-foundation has no async URLSession.data(for:) on all
        // versions; bridge the completion-handler API.
        (data, response) = try await withCheckedThrowingContinuation { continuation in
            session.dataTask(with: urlRequest) { data, response, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let data, let response {
                    continuation.resume(returning: (data, response))
                } else {
                    continuation.resume(throwing: StudioError.io(
                        path: request.url.absoluteString, detail: "empty response"))
                }
            }.resume()
        }
        #else
        (data, response) = try await session.data(for: urlRequest)
        #endif
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        return HTTPResponse(status: status, body: data)
    }
}
