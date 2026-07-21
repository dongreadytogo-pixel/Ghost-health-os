import Foundation
import GhostlyCore

/// Anthropic Messages API adapter (Claude).
public struct AnthropicProvider: LLMProvider {
    public let name = "anthropic"
    public let capabilities: Set<AICapability> = [.editing, .summarization, .vision, .codegen]

    private let apiKey: String
    private let model: String
    private let baseURL: URL
    private let transport: any HTTPTransport

    public init(apiKey: String, model: String = "claude-sonnet-5",
                baseURL: URL = URL(string: "https://api.anthropic.com")!,
                transport: any HTTPTransport = URLSessionTransport()) {
        self.apiKey = apiKey
        self.model = model
        self.baseURL = baseURL
        self.transport = transport
    }

    public func complete(_ request: LLMRequest) async throws -> LLMResponse {
        let model = request.model ?? self.model
        let system = request.messages.filter { $0.role == .system }.map(\.content).joined(separator: "\n")
        let turns = request.messages.filter { $0.role != .system }.map {
            ["role": $0.role.rawValue, "content": $0.content]
        }
        var payload: [String: Any] = [
            "model": model,
            "max_tokens": request.maxTokens,
            "temperature": request.temperature,
            "messages": turns,
        ]
        if !system.isEmpty { payload["system"] = system }

        let response = try await transport.send(HTTPRequest(
            url: baseURL.appendingPathComponent("v1/messages"),
            headers: [
                "content-type": "application/json",
                "x-api-key": apiKey,
                "anthropic-version": "2023-06-01",
            ],
            body: try JSONSerialization.data(withJSONObject: payload)))
        let json = try Self.jsonObject(response, provider: name)
        guard let content = json["content"] as? [[String: Any]],
              let text = content.compactMap({ $0["text"] as? String }).first else {
            throw StudioError.provider(name: name, detail: "response missing content text")
        }
        let usage = json["usage"] as? [String: Any]
        return LLMResponse(text: text,
                           model: json["model"] as? String ?? model,
                           inputTokens: usage?["input_tokens"] as? Int,
                           outputTokens: usage?["output_tokens"] as? Int)
    }

    static func jsonObject(_ response: HTTPResponse, provider: String) throws -> [String: Any] {
        guard (200..<300).contains(response.status) else {
            let body = String(data: response.body, encoding: .utf8) ?? ""
            throw StudioError.provider(name: provider,
                                       detail: "HTTP \(response.status): \(body.prefix(300))")
        }
        guard let json = try? JSONSerialization.jsonObject(with: response.body) as? [String: Any] else {
            throw StudioError.provider(name: provider, detail: "response is not a JSON object")
        }
        return json
    }
}

/// OpenAI-compatible Chat Completions adapter. Covers OpenAI itself plus the
/// many engines that speak the same protocol: LM Studio, Ollama's
/// `/v1` endpoint, Qwen, Mistral, DeepSeek, vLLM, …
public struct OpenAICompatibleProvider: LLMProvider {
    public let name: String
    public let capabilities: Set<AICapability>

    private let apiKey: String?
    private let model: String
    private let baseURL: URL
    private let transport: any HTTPTransport

    public init(name: String = "openai", apiKey: String?, model: String = "gpt-4o",
                baseURL: URL = URL(string: "https://api.openai.com/v1")!,
                capabilities: Set<AICapability> = [.editing, .summarization, .codegen],
                transport: any HTTPTransport = URLSessionTransport()) {
        self.name = name
        self.apiKey = apiKey
        self.model = model
        self.baseURL = baseURL
        self.capabilities = capabilities
        self.transport = transport
    }

    /// LM Studio's local server with its default port.
    public static func lmStudio(model: String,
                                transport: any HTTPTransport = URLSessionTransport()) -> OpenAICompatibleProvider {
        OpenAICompatibleProvider(name: "lmstudio", apiKey: nil, model: model,
                                 baseURL: URL(string: "http://localhost:1234/v1")!,
                                 capabilities: [.editing, .summarization, .codegen, .local],
                                 transport: transport)
    }

    public func complete(_ request: LLMRequest) async throws -> LLMResponse {
        let model = request.model ?? self.model
        let payload: [String: Any] = [
            "model": model,
            "max_tokens": request.maxTokens,
            "temperature": request.temperature,
            "messages": request.messages.map { ["role": $0.role.rawValue, "content": $0.content] },
        ]
        var headers = ["content-type": "application/json"]
        if let apiKey { headers["authorization"] = "Bearer \(apiKey)" }
        let response = try await transport.send(HTTPRequest(
            url: baseURL.appendingPathComponent("chat/completions"),
            headers: headers,
            body: try JSONSerialization.data(withJSONObject: payload)))
        let json = try AnthropicProvider.jsonObject(response, provider: name)
        guard let choices = json["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let text = message["content"] as? String else {
            throw StudioError.provider(name: name, detail: "response missing choices content")
        }
        let usage = json["usage"] as? [String: Any]
        return LLMResponse(text: text,
                           model: json["model"] as? String ?? model,
                           inputTokens: usage?["prompt_tokens"] as? Int,
                           outputTokens: usage?["completion_tokens"] as? Int)
    }
}

/// Ollama native API adapter for fully local models.
public struct OllamaProvider: LLMProvider {
    public let name = "ollama"
    public let capabilities: Set<AICapability> = [.fast, .local, .summarization, .editing]

    private let model: String
    private let baseURL: URL
    private let transport: any HTTPTransport

    public init(model: String = "llama3.1",
                baseURL: URL = URL(string: "http://localhost:11434")!,
                transport: any HTTPTransport = URLSessionTransport()) {
        self.model = model
        self.baseURL = baseURL
        self.transport = transport
    }

    public func complete(_ request: LLMRequest) async throws -> LLMResponse {
        let model = request.model ?? self.model
        let payload: [String: Any] = [
            "model": model,
            "stream": false,
            "options": ["temperature": request.temperature, "num_predict": request.maxTokens],
            "messages": request.messages.map { ["role": $0.role.rawValue, "content": $0.content] },
        ]
        let response = try await transport.send(HTTPRequest(
            url: baseURL.appendingPathComponent("api/chat"),
            headers: ["content-type": "application/json"],
            body: try JSONSerialization.data(withJSONObject: payload)))
        let json = try AnthropicProvider.jsonObject(response, provider: name)
        guard let message = json["message"] as? [String: Any],
              let text = message["content"] as? String else {
            throw StudioError.provider(name: name, detail: "response missing message content")
        }
        return LLMResponse(text: text, model: model,
                           inputTokens: json["prompt_eval_count"] as? Int,
                           outputTokens: json["eval_count"] as? Int)
    }
}

/// Google Gemini generateContent adapter.
public struct GeminiProvider: LLMProvider {
    public let name = "gemini"
    public let capabilities: Set<AICapability> = [.editing, .summarization, .vision, .fast]

    private let apiKey: String
    private let model: String
    private let baseURL: URL
    private let transport: any HTTPTransport

    public init(apiKey: String, model: String = "gemini-2.0-flash",
                baseURL: URL = URL(string: "https://generativelanguage.googleapis.com")!,
                transport: any HTTPTransport = URLSessionTransport()) {
        self.apiKey = apiKey
        self.model = model
        self.baseURL = baseURL
        self.transport = transport
    }

    public func complete(_ request: LLMRequest) async throws -> LLMResponse {
        let model = request.model ?? self.model
        let system = request.messages.filter { $0.role == .system }.map(\.content).joined(separator: "\n")
        let contents = request.messages.filter { $0.role != .system }.map { message in
            ["role": message.role == .assistant ? "model" : "user",
             "parts": [["text": message.content]]] as [String: Any]
        }
        var payload: [String: Any] = [
            "contents": contents,
            "generationConfig": ["temperature": request.temperature,
                                 "maxOutputTokens": request.maxTokens],
        ]
        if !system.isEmpty {
            payload["systemInstruction"] = ["parts": [["text": system]]]
        }
        let url = baseURL.appendingPathComponent("v1beta/models/\(model):generateContent")
        let response = try await transport.send(HTTPRequest(
            url: url,
            headers: ["content-type": "application/json", "x-goog-api-key": apiKey],
            body: try JSONSerialization.data(withJSONObject: payload)))
        let json = try AnthropicProvider.jsonObject(response, provider: name)
        guard let candidates = json["candidates"] as? [[String: Any]],
              let content = candidates.first?["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]],
              let text = parts.compactMap({ $0["text"] as? String }).first else {
            throw StudioError.provider(name: name, detail: "response missing candidate text")
        }
        return LLMResponse(text: text, model: model)
    }
}
