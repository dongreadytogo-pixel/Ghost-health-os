import XCTest
import GhostlyCore
@testable import GhostlyMCP

final class MCPTests: XCTestCase {
    private var preferencesDir: URL!

    override func setUpWithError() throws {
        preferencesDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ghostly-mcp-tests-\(UUID().uuidString)")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: preferencesDir)
    }

    private func makeServer() async throws -> MCPServer {
        try await GhostlyMCPFactory.makeServer(preferencesDirectory: preferencesDir)
    }

    private func send(_ server: MCPServer, _ json: String) async -> JSONValue? {
        await server.handle(Data(json.utf8))
    }

    /// Extracts the text content of a successful tools/call response.
    private func toolText(_ response: JSONValue?) throws -> (text: String, isError: Bool) {
        let result = try XCTUnwrap(response?["result"])
        let content = try XCTUnwrap(result["content"]?.arrayValue?.first)
        return (try XCTUnwrap(content["text"]?.stringValue),
                result["isError"]?.boolValue ?? false)
    }

    // MARK: Protocol lifecycle

    func testInitializeHandshake() async throws {
        let server = try await makeServer()
        let response = await send(server, """
        {"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{}}}
        """)
        let result = try XCTUnwrap(response?["result"])
        XCTAssertEqual(result["protocolVersion"]?.stringValue, "2024-11-05")
        XCTAssertEqual(result["serverInfo"]?["name"]?.stringValue, "ghostly-studio")
        XCTAssertNotNil(result["capabilities"]?["tools"])
    }

    func testNotificationGetsNoResponse() async throws {
        let server = try await makeServer()
        let response = await send(server, """
        {"jsonrpc":"2.0","method":"notifications/initialized"}
        """)
        XCTAssertNil(response)
    }

    func testToolsListExposesAllStudioTools() async throws {
        let server = try await makeServer()
        let response = await send(server, #"{"jsonrpc":"2.0","id":2,"method":"tools/list"}"#)
        let tools = try XCTUnwrap(response?["result"]?["tools"]?.arrayValue)
        let names = tools.compactMap { $0["name"]?.stringValue }
        XCTAssertEqual(Set(names), ["auto_edit", "parse_edit_command", "generate_captions",
                                    "validate_fcpxml", "analyze_timeline", "find_highlights",
                                    "list_caption_styles", "recommend"])
        for tool in tools {
            XCTAssertNotNil(tool["description"]?.stringValue)
            XCTAssertNotNil(tool["inputSchema"]?["type"])
        }
    }

    func testMalformedJSONYieldsParseError() async throws {
        let server = try await makeServer()
        let response = await send(server, "{nope")
        XCTAssertEqual(response?["error"]?["code"]?.intValue, JSONRPCError.parseError)
    }

    func testUnknownMethodAndUnknownTool() async throws {
        let server = try await makeServer()
        let bad = await send(server, #"{"jsonrpc":"2.0","id":3,"method":"resources/list"}"#)
        XCTAssertEqual(bad?["error"]?["code"]?.intValue, JSONRPCError.methodNotFound)

        let badTool = await send(server, """
        {"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"no_such_tool","arguments":{}}}
        """)
        XCTAssertEqual(badTool?["error"]?["code"]?.intValue, JSONRPCError.methodNotFound)
    }

    // MARK: Tools end-to-end

    func testAutoEditToolProducesValidFCPXML() async throws {
        let server = try await makeServer()
        let call = """
        {"jsonrpc":"2.0","id":5,"method":"tools/call","params":{"name":"auto_edit","arguments":{
            "command":"create a tiktok, remove silence",
            "projectName":"Short 1",
            "footage":[{"name":"talk","url":"file:///media/talk.mov","durationSeconds":30,
                        "speechRanges":[[1,9],[12,26]]}],
            "transcriptSRT":"1\\n00:00:01,000 --> 00:00:03,000\\nhello world\\n"
        }}}
        """
        let (text, isError) = try toolText(await send(server, call))
        XCTAssertFalse(isError, text)
        XCTAssertTrue(text.contains("<fcpxml"))
        XCTAssertTrue(text.contains("HELLO WORLD"), "TikTok captions are upcased")

        // The emitted document must satisfy our own validator via the tool.
        let validate: JSONValue = .object([
            "jsonrpc": "2.0", "id": 6, "method": "tools/call",
            "params": .object(["name": "validate_fcpxml",
                               "arguments": .object(["fcpxml": .string(text)])]),
        ])
        let (validation, vError) = try toolText(await server.handle(validate.encoded()))
        XCTAssertFalse(vError)
        XCTAssertTrue(validation.contains("\"valid\":true"), validation)
    }

    func testAutoEditToolReportsBadInputAsToolError() async throws {
        let server = try await makeServer()
        let call = """
        {"jsonrpc":"2.0","id":7,"method":"tools/call","params":{"name":"auto_edit","arguments":{
            "command":"create a tiktok","footage":[]}}}
        """
        let (text, isError) = try toolText(await send(server, call))
        XCTAssertTrue(isError)
        XCTAssertTrue(text.contains("footage"), text)
    }

    func testParseCommandTool() async throws {
        let server = try await makeServer()
        let call = """
        {"jsonrpc":"2.0","id":8,"method":"tools/call","params":{"name":"parse_edit_command",
         "arguments":{"command":"edit this like marvel and cut to the beat"}}}
        """
        let (text, isError) = try toolText(await send(server, call))
        XCTAssertFalse(isError)
        XCTAssertTrue(text.contains("Marvel"))
        XCTAssertTrue(text.contains("\"cutOnBeats\":true"))
    }

    func testGenerateCaptionsTool() async throws {
        let server = try await makeServer()
        let call: JSONValue = .object([
            "jsonrpc": "2.0", "id": 9, "method": "tools/call",
            "params": .object([
                "name": "generate_captions",
                "arguments": .object([
                    "subtitles": "1\n00:00:00,500 --> 00:00:02,000\nhello there\n",
                    "style": "TikTok",
                    "shiftSeconds": .number(1),
                ]),
            ]),
        ])
        let (text, isError) = try toolText(await server.handle(call.encoded()))
        XCTAssertFalse(isError)
        XCTAssertTrue(text.contains("HELLO THERE"))
        XCTAssertTrue(text.contains("00:00:01,500"), "shift must be applied: \(text)")
    }

    func testAnalyzeTimelineToolRoundTripsAutoEditOutput() async throws {
        let server = try await makeServer()
        let edit = """
        {"jsonrpc":"2.0","id":10,"method":"tools/call","params":{"name":"auto_edit","arguments":{
            "command":"edit this like a documentary",
            "footage":[{"name":"a","url":"file:///a.mov","durationSeconds":40,
                        "speechRanges":[[0,18],[20,38]]}]}}}
        """
        let (fcpxml, editError) = try toolText(await send(server, edit))
        XCTAssertFalse(editError, fcpxml)

        let analyze: JSONValue = .object([
            "jsonrpc": "2.0", "id": 11, "method": "tools/call",
            "params": .object(["name": "analyze_timeline",
                               "arguments": .object(["fcpxml": .string(fcpxml)])]),
        ])
        let (report, analyzeError) = try toolText(await server.handle(analyze.encoded()))
        XCTAssertFalse(analyzeError)
        XCTAssertTrue(report.contains("\"problems\":[]"), report)
        XCTAssertTrue(report.contains("storylineClips"))
    }

    func testFindHighlightsTool() async throws {
        let server = try await makeServer()
        let call = """
        {"jsonrpc":"2.0","id":20,"method":"tools/call","params":{"name":"find_highlights",
         "arguments":{"footage":{"name":"talk","url":"file:///t.mov","durationSeconds":40,
         "speechRanges":[[5,35]],"sceneCuts":[15,30]},"limit":3}}}
        """
        let (text, isError) = try toolText(await send(server, call))
        XCTAssertFalse(isError, text)
        XCTAssertTrue(text.contains("\"highlights\""))
        XCTAssertTrue(text.contains("\"chapters\""))
        XCTAssertTrue(text.contains("hook") || text.contains("highlight"))
    }

    func testListStylesAndRecommendTools() async throws {
        let server = try await makeServer()
        let (styles, _) = try toolText(await send(server,
            #"{"jsonrpc":"2.0","id":12,"method":"tools/call","params":{"name":"list_caption_styles","arguments":{}}}"#))
        XCTAssertTrue(styles.contains("TikTok"))
        XCTAssertTrue(styles.contains("Broadcast"))

        let (recs, recError) = try toolText(await send(server,
            #"{"jsonrpc":"2.0","id":13,"method":"tools/call","params":{"name":"recommend","arguments":{"category":"transition"}}}"#))
        XCTAssertFalse(recError)
        XCTAssertTrue(recs.contains("\"recommendations\":[]"), "fresh store has no data: \(recs)")

        let (bad, badIsError) = try toolText(await send(server,
            #"{"jsonrpc":"2.0","id":14,"method":"tools/call","params":{"name":"recommend","arguments":{"category":"nonsense"}}}"#))
        XCTAssertTrue(badIsError)
        XCTAssertTrue(bad.contains("must be one of"))
    }

    // MARK: JSONValue

    func testJSONValueRoundTripAndAccessors() throws {
        let value = try JSONValue(from: Data(#"{"a":1,"b":[true,null,"x"],"c":{"d":2.5}}"#.utf8))
        XCTAssertEqual(value["a"]?.intValue, 1)
        XCTAssertEqual(value["b"]?.arrayValue?.count, 3)
        XCTAssertEqual(value["b"]?.arrayValue?[0].boolValue, true)
        XCTAssertEqual(value["b"]?.arrayValue?[1], .null)
        XCTAssertEqual(value["c"]?["d"]?.numberValue, 2.5)

        let reparsed = try JSONValue(from: value.encoded())
        XCTAssertEqual(reparsed, value)
    }

    func testJSONValueDistinguishesBoolFromNumber() throws {
        let value = try JSONValue(from: Data(#"{"flag":true,"one":1}"#.utf8))
        XCTAssertEqual(value["flag"], .bool(true))
        XCTAssertEqual(value["one"], .number(1))
        XCTAssertNil(value["flag"]?.numberValue)
    }
}
