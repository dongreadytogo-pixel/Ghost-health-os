import XCTest
import GhostlyCore
@testable import GhostlyAI

/// Records requests and plays back scripted responses.
final class MockTransport: HTTPTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var responses: [HTTPResponse]
    private(set) var requests: [HTTPRequest] = []

    init(responses: [HTTPResponse]) {
        self.responses = responses
    }

    convenience init(status: Int = 200, json: String) {
        self.init(responses: [HTTPResponse(status: status, body: Data(json.utf8))])
    }

    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        lock.lock()
        defer { lock.unlock() }
        requests.append(request)
        guard !responses.isEmpty else {
            throw StudioError.io(path: request.url.absoluteString, detail: "no scripted response")
        }
        return responses.removeFirst()
    }
}

struct StubProvider: LLMProvider {
    let name: String
    let capabilities: Set<AICapability>
    var result: Result<String, StudioError> = .success("ok")

    func complete(_ request: LLMRequest) async throws -> LLMResponse {
        switch result {
        case .success(let text): return LLMResponse(text: text, model: name)
        case .failure(let error): throw error
        }
    }
}

final class AITests: XCTestCase {
    // MARK: Anthropic adapter

    func testAnthropicRequestAndResponse() async throws {
        let transport = MockTransport(json: """
        {"model":"claude-sonnet-5","content":[{"type":"text","text":"cut faster"}],
         "usage":{"input_tokens":10,"output_tokens":3}}
        """)
        let provider = AnthropicProvider(apiKey: "sk-test", transport: transport)
        let response = try await provider.complete(LLMRequest(messages: [
            .system("be brief"), .user("how should I pace this?"),
        ]))

        XCTAssertEqual(response.text, "cut faster")
        XCTAssertEqual(response.inputTokens, 10)

        let request = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(request.url.absoluteString, "https://api.anthropic.com/v1/messages")
        XCTAssertEqual(request.headers["x-api-key"], "sk-test")
        let body = try XCTUnwrap(try JSONSerialization.jsonObject(with: request.body!) as? [String: Any])
        XCTAssertEqual(body["system"] as? String, "be brief")
        let messages = try XCTUnwrap(body["messages"] as? [[String: Any]])
        XCTAssertEqual(messages.count, 1, "system message must not appear in messages array")
    }

    func testAnthropicSurfacesHTTPErrors() async {
        let transport = MockTransport(status: 429, json: #"{"error":"rate_limited"}"#)
        let provider = AnthropicProvider(apiKey: "k", transport: transport)
        do {
            _ = try await provider.complete(LLMRequest(messages: [.user("x")]))
            XCTFail("expected error")
        } catch let StudioError.provider(name, detail) {
            XCTAssertEqual(name, "anthropic")
            XCTAssertTrue(detail.contains("429"))
        } catch {
            XCTFail("wrong error type: \(error)")
        }
    }

    // MARK: OpenAI-compatible adapter

    func testOpenAICompatibleParsesChoices() async throws {
        let transport = MockTransport(json: """
        {"model":"gpt-4o","choices":[{"message":{"role":"assistant","content":"plan ready"}}],
         "usage":{"prompt_tokens":7,"completion_tokens":2}}
        """)
        let provider = OpenAICompatibleProvider(apiKey: "k", transport: transport)
        let response = try await provider.complete(LLMRequest(messages: [.user("hi")]))
        XCTAssertEqual(response.text, "plan ready")
        XCTAssertEqual(response.outputTokens, 2)
        let request = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(request.headers["authorization"], "Bearer k")
    }

    func testLMStudioPresetIsLocalAndUnauthenticated() async throws {
        let transport = MockTransport(json: """
        {"choices":[{"message":{"content":"local answer"}}]}
        """)
        let provider = OpenAICompatibleProvider.lmStudio(model: "qwen2.5", transport: transport)
        XCTAssertTrue(provider.capabilities.contains(.local))
        _ = try await provider.complete(LLMRequest(messages: [.user("hi")]))
        let request = try XCTUnwrap(transport.requests.first)
        XCTAssertNil(request.headers["authorization"])
        XCTAssertTrue(request.url.absoluteString.hasPrefix("http://localhost:1234/v1"))
    }

    // MARK: Ollama + Gemini adapters

    func testOllamaParsesMessage() async throws {
        let transport = MockTransport(json: """
        {"message":{"role":"assistant","content":"llama says hi"},"eval_count":5}
        """)
        let provider = OllamaProvider(transport: transport)
        let response = try await provider.complete(LLMRequest(messages: [.user("hi")]))
        XCTAssertEqual(response.text, "llama says hi")
        XCTAssertEqual(response.outputTokens, 5)
    }

    func testGeminiParsesCandidatesAndMapsRoles() async throws {
        let transport = MockTransport(json: """
        {"candidates":[{"content":{"parts":[{"text":"gemini reply"}],"role":"model"}}]}
        """)
        let provider = GeminiProvider(apiKey: "k", transport: transport)
        let response = try await provider.complete(LLMRequest(messages: [
            .system("sys"), .user("u"), .assistant("a"), .user("u2"),
        ]))
        XCTAssertEqual(response.text, "gemini reply")
        let request = try XCTUnwrap(transport.requests.first)
        let body = try XCTUnwrap(try JSONSerialization.jsonObject(with: request.body!) as? [String: Any])
        let contents = try XCTUnwrap(body["contents"] as? [[String: Any]])
        XCTAssertEqual(contents.map { $0["role"] as? String }, ["user", "model", "user"])
        XCTAssertNotNil(body["systemInstruction"])
    }

    func testMalformedProviderResponseThrows() async {
        let provider = OllamaProvider(transport: MockTransport(json: #"{"unexpected":true}"#))
        do {
            _ = try await provider.complete(LLMRequest(messages: [.user("x")]))
            XCTFail("expected error")
        } catch let StudioError.provider(name, _) {
            XCTAssertEqual(name, "ollama")
        } catch {
            XCTFail("wrong error: \(error)")
        }
    }

    // MARK: Router

    func testRouterPicksCapableProviderByPriority() async throws {
        let router = ModelRouter()
        await router.register(StubProvider(name: "small", capabilities: [.fast]), priority: 10)
        await router.register(StubProvider(name: "big", capabilities: [.editing, .vision],
                                           result: .success("from big")), priority: 1)
        let response = try await router.complete(LLMRequest(messages: [.user("x")]),
                                                 capability: .editing)
        XCTAssertEqual(response.text, "from big")
    }

    func testRouterFallsBackOnFailure() async throws {
        let router = ModelRouter()
        await router.register(StubProvider(name: "flaky", capabilities: [.editing],
                                           result: .failure(.provider(name: "flaky", detail: "down"))),
                              priority: 10)
        await router.register(StubProvider(name: "backup", capabilities: [.editing],
                                           result: .success("rescued")), priority: 1)
        let response = try await router.complete(LLMRequest(messages: [.user("x")]))
        XCTAssertEqual(response.text, "rescued")
    }

    func testRouterThrowsWhenNoCapableProvider() async {
        let router = ModelRouter()
        await router.register(StubProvider(name: "textonly", capabilities: [.summarization]))
        do {
            _ = try await router.complete(LLMRequest(messages: [.user("x")]), capability: .vision)
            XCTFail("expected error")
        } catch let StudioError.notFound(entity, id) {
            XCTAssertEqual(entity, "LLMProvider")
            XCTAssertEqual(id, "vision")
        } catch {
            XCTFail("wrong error: \(error)")
        }
    }

    func testRouterPreferLocalPolicy() async throws {
        let router = ModelRouter(policy: .preferLocal)
        await router.register(StubProvider(name: "cloud", capabilities: [.editing],
                                           result: .success("cloud")), priority: 100)
        await router.register(StubProvider(name: "onbox", capabilities: [.editing, .local],
                                           result: .success("local")), priority: 0)
        let response = try await router.complete(LLMRequest(messages: [.user("x")]))
        XCTAssertEqual(response.text, "local")
    }

    func testRouterExhaustedPropagatesLastError() async {
        let router = ModelRouter()
        await router.register(StubProvider(name: "a", capabilities: [.editing],
                                           result: .failure(.provider(name: "a", detail: "first"))))
        await router.register(StubProvider(name: "b", capabilities: [.editing],
                                           result: .failure(.provider(name: "b", detail: "second"))))
        do {
            _ = try await router.complete(LLMRequest(messages: [.user("x")]))
            XCTFail("expected error")
        } catch let StudioError.provider(name, _) {
            XCTAssertEqual(name, "b", "last failure wins")
        } catch {
            XCTFail("wrong error: \(error)")
        }
    }

    func testTemperatureClamping() {
        XCTAssertEqual(LLMRequest(messages: [], temperature: 9).temperature, 2)
        XCTAssertEqual(LLMRequest(messages: [], temperature: -1).temperature, 0)
    }
}
