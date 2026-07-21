import XCTest
import GhostlyCore
import GhostlyDetection
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
                                    "search_assets", "export_command", "list_export_presets",
                                    "validate_plugin_manifest", "list_caption_styles", "recommend",
                                    "analyze_audio", "edit_from_audio", "run_workflow",
                                    "export_chapters"])
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

    func testExportChaptersToolFormatsAndValidates() async throws {
        let server = try await makeServer()
        let srt = "1\\n00:00:01,000 --> 00:00:20,000\\nบทนำ\\n\\n2\\n00:00:40,000 --> 00:01:00,000\\nช่วงสอง\\n\\n3\\n00:01:20,000 --> 00:01:40,000\\nช่วงสาม\\n"
        let call = """
        {"jsonrpc":"2.0","id":50,"method":"tools/call","params":{"name":"export_chapters","arguments":{
            "transcriptSRT":"\(srt)","durationSeconds":120}}}
        """
        let (text, isError) = try toolText(await send(server, call))
        XCTAssertFalse(isError, text)
        XCTAssertTrue(text.contains("\"valid\":true"), text)
        XCTAssertTrue(text.contains("0:00 "), "chapters must start at 0:00: \(text)")

        // Too short for YouTube's rules → valid=false with a Thai reason.
        let short = """
        {"jsonrpc":"2.0","id":51,"method":"tools/call","params":{"name":"export_chapters","arguments":{
            "transcriptSRT":"1\\n00:00:01,000 --> 00:00:05,000\\nสั้น\\n","durationSeconds":12}}}
        """
        let (invalid, shortError) = try toolText(await send(server, short))
        XCTAssertFalse(shortError, invalid)
        XCTAssertTrue(invalid.contains("\"valid\":false"), invalid)
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

    func testAutoEditToolThaiCaptions() async throws {
        let server = try await makeServer()
        let call = """
        {"jsonrpc":"2.0","id":40,"method":"tools/call","params":{"name":"auto_edit","arguments":{
            "command":"create a tiktok with captions",
            "language":"th",
            "footage":[{"name":"talk","url":"file:///media/talk.mov","durationSeconds":12,
                        "speechRanges":[[1,4],[5,10]]}],
            "transcriptSRT":"1\\n00:00:01,000 --> 00:00:03,000\\nสวัสดีครับ\\n"
        }}}
        """
        let (text, isError) = try toolText(await send(server, call))
        XCTAssertFalse(isError, text)
        XCTAssertTrue(text.contains("captionFormat=ITT.th"), "Thai language must tag the caption role")
        XCTAssertTrue(text.contains("สวัสดีครับ"))
    }

    // MARK: Audio tools (real-audio pipeline over MCP)

    /// Writes a two-voice fixture WAV into the test directory.
    private func writeInterviewWAV() throws -> String {
        let fixture = AudioFixture(sampleRate: 16_000)
            .silence(1.0).tone(frequency: 150, seconds: 1.5)
            .silence(1.0).tone(frequency: 310, seconds: 2.0)
            .silence(0.5)
        try FileManager.default.createDirectory(at: preferencesDir,
                                                withIntermediateDirectories: true)
        let url = preferencesDir.appendingPathComponent("interview.wav")
        try fixture.wavData().write(to: url)
        return url.path
    }

    func testAnalyzeAudioTool() async throws {
        let server = try await makeServer()
        let path = try writeInterviewWAV()
        let call = """
        {"jsonrpc":"2.0","id":50,"method":"tools/call","params":{"name":"analyze_audio",
            "arguments":{"audioPath":"\(path)","diarize":true}}}
        """
        let (text, isError) = try toolText(await send(server, call))
        XCTAssertFalse(isError, text)
        XCTAssertTrue(text.contains("speechRanges"))
        XCTAssertTrue(text.contains("\"speakerCount\":2") || text.contains("\"speakerCount\": 2"),
                      "two distinct voices expected: \(text)")
    }

    func testAnalyzeAudioToolMissingFileIsToolError() async throws {
        let server = try await makeServer()
        let call = """
        {"jsonrpc":"2.0","id":51,"method":"tools/call","params":{"name":"analyze_audio",
            "arguments":{"audioPath":"/nonexistent/file.wav"}}}
        """
        let (text, isError) = try toolText(await send(server, call))
        XCTAssertTrue(isError, text)
    }

    func testEditFromAudioToolProducesThaiFCPXML() async throws {
        let server = try await makeServer()
        let path = try writeInterviewWAV()
        let call = """
        {"jsonrpc":"2.0","id":52,"method":"tools/call","params":{"name":"edit_from_audio",
            "arguments":{"audioPath":"\(path)",
            "command":"create a tiktok with captions",
            "diarize":true,
            "transcriptSRT":"1\\n00:00:01,000 --> 00:00:02,500\\nสวัสดีครับ\\n\\n2\\n00:00:03,500 --> 00:00:05,500\\nสบายดีค่ะ\\n"}}}
        """
        let (text, isError) = try toolText(await send(server, call))
        XCTAssertFalse(isError, text)
        XCTAssertTrue(text.contains("captionFormat=ITT.th"),
                      "default language must be Thai: \(text.prefix(400))")
        XCTAssertTrue(text.contains("สวัสดีครับ"))
    }

    func testRunWorkflowToolChainsToExportCommand() async throws {
        let server = try await makeServer()
        let path = try writeInterviewWAV()
        let call = """
        {"jsonrpc":"2.0","id":53,"method":"tools/call","params":{"name":"run_workflow",
            "arguments":{"audioPath":"\(path)","command":"create a tiktok, remove silence"}}}
        """
        let (text, isError) = try toolText(await send(server, call))
        XCTAssertFalse(isError, text)
        XCTAssertTrue(text.contains("\"exportPreset\":\"TikTok\""), String(text.prefix(300)))
        XCTAssertTrue(text.contains("scale=1080:1920"), "export command must be included")
        XCTAssertTrue(text.contains("\"steps\""))
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

    func testSearchAssetsTool() async throws {
        let server = try await makeServer()
        let call = """
        {"jsonrpc":"2.0","id":21,"method":"tools/call","params":{"name":"search_assets",
         "arguments":{"query":"vertical drone clips","assets":[
           {"name":"drone_flyover","url":"file:///d.mov","durationSeconds":12,"kind":"video","width":1080,"height":1920},
           {"name":"interview","url":"file:///i.mov","durationSeconds":300,"kind":"video","width":1920,"height":1080}
         ]}}}
        """
        let (text, isError) = try toolText(await send(server, call))
        XCTAssertFalse(isError, text)
        XCTAssertTrue(text.contains("drone_flyover"))
        XCTAssertFalse(text.contains("interview"), "horizontal interview must not match a vertical query")
        XCTAssertTrue(text.contains("vertical"), "auto-tagging should add a vertical tag")
    }

    func testExportCommandTool() async throws {
        let server = try await makeServer()
        let call = """
        {"jsonrpc":"2.0","id":22,"method":"tools/call","params":{"name":"export_command",
         "arguments":{"input":"in.mov","output":"out.mp4","preset":"TikTok","title":"My Clip"}}}
        """
        let (text, isError) = try toolText(await send(server, call))
        XCTAssertFalse(isError, text)
        XCTAssertTrue(text.contains("1080x1920"), "TikTok is vertical")
        XCTAssertTrue(text.contains("libx264"))
        XCTAssertTrue(text.contains("commandLine"))
        XCTAssertTrue(text.contains("My Clip"))
    }

    func testExportCommandUnknownPresetIsToolError() async throws {
        let server = try await makeServer()
        let call = """
        {"jsonrpc":"2.0","id":23,"method":"tools/call","params":{"name":"export_command",
         "arguments":{"input":"in.mov","output":"out.mp4","preset":"nonsense"}}}
        """
        let (text, isError) = try toolText(await send(server, call))
        XCTAssertTrue(isError)
        XCTAssertTrue(text.contains("RenderPreset"))
    }

    func testListExportPresetsTool() async throws {
        let server = try await makeServer()
        let (text, _) = try toolText(await send(server,
            #"{"jsonrpc":"2.0","id":24,"method":"tools/call","params":{"name":"list_export_presets","arguments":{}}}"#))
        XCTAssertTrue(text.contains("TikTok"))
        XCTAssertTrue(text.contains("YouTube 4K"))
    }

    func testGenerateCaptionsAutoPunctuate() async throws {
        let server = try await makeServer()
        let call: JSONValue = .object([
            "jsonrpc": "2.0", "id": 30, "method": "tools/call",
            "params": .object([
                "name": "generate_captions",
                "arguments": .object([
                    "subtitles": "1\n00:00:00,000 --> 00:00:02,000\nhow are you today\n",
                    "style": "YouTube",
                    "autoPunctuate": .bool(true),
                ]),
            ]),
        ])
        let (text, isError) = try toolText(await server.handle(call.encoded()))
        XCTAssertFalse(isError, text)
        XCTAssertTrue(text.contains("How are you today?"),
                      "raw ASR line should be capitalized + question-marked: \(text)")
    }

    func testValidatePluginManifestTool() async throws {
        let server = try await makeServer()
        let manifest = """
        {"id":"com.example.pack","name":"Pack","version":"1.2.0",
         "minStudioVersion":"1.0.0","author":"Me","entryPoint":"Pack.bundle",
         "permissions":["network"],"contributes":["mcpTools"]}
        """
        let call: JSONValue = .object([
            "jsonrpc": "2.0", "id": 31, "method": "tools/call",
            "params": .object([
                "name": "validate_plugin_manifest",
                "arguments": .object(["manifest": .string(manifest), "studioVersion": "1.5.0"]),
            ]),
        ])
        let (text, isError) = try toolText(await server.handle(call.encoded()))
        XCTAssertFalse(isError, text)
        XCTAssertTrue(text.contains("\"valid\":true"))
        XCTAssertTrue(text.contains("\"compatible\":true"))
        XCTAssertTrue(text.contains("com.example.pack"))
    }

    func testValidatePluginManifestRejectsBad() async throws {
        let server = try await makeServer()
        let call: JSONValue = .object([
            "jsonrpc": "2.0", "id": 32, "method": "tools/call",
            "params": .object([
                "name": "validate_plugin_manifest",
                "arguments": .object(["manifest": "{\"id\":\"notdns\",\"name\":\"x\"}"]),
            ]),
        ])
        let (text, isError) = try toolText(await server.handle(call.encoded()))
        XCTAssertTrue(isError, "invalid manifest must be a tool error: \(text)")
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
