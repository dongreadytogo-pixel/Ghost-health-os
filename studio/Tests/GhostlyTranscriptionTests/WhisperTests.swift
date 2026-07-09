import XCTest
import GhostlyCore
import GhostlySubtitles
@testable import GhostlyTranscription

final class WhisperTests: XCTestCase {
    /// Realistic whisper.cpp full-JSON output for a Thai clip (subset of fields).
    private let thaiWhisperJSON = """
    {
      "systeminfo": "AVX = 1",
      "result": { "language": "th" },
      "transcription": [
        {
          "timestamps": { "from": "00:00:00,000", "to": "00:00:02,500" },
          "offsets": { "from": 0, "to": 2500 },
          "text": " สวัสดีครับทุกคน",
          "tokens": [
            { "text": "[_BEG_]", "offsets": { "from": 0, "to": 0 }, "p": 0.99 },
            { "text": "สวัสดี", "offsets": { "from": 0, "to": 900 }, "p": 0.95 },
            { "text": "ครับ", "offsets": { "from": 900, "to": 1500 }, "p": 0.93 },
            { "text": "ทุกคน", "offsets": { "from": 1500, "to": 2500 }, "p": 0.91 },
            { "text": "[_TT_125]", "offsets": { "from": 2500, "to": 2500 }, "p": 0.5 }
          ]
        },
        {
          "timestamps": { "from": "00:00:03,000", "to": "00:00:05,000" },
          "offsets": { "from": 3000, "to": 5000 },
          "text": " วันนี้อากาศดีมาก",
          "tokens": [
            { "text": "วันนี้", "offsets": { "from": 3000, "to": 3800 }, "p": 0.94 },
            { "text": "อากาศ", "offsets": { "from": 3800, "to": 4400 }, "p": 0.92 },
            { "text": "ดีมาก", "offsets": { "from": 4400, "to": 5000 }, "p": 0.90 }
          ]
        }
      ]
    }
    """

    // MARK: Parser

    func testParsesThaiSegmentsAndLanguage() throws {
        let track = try WhisperJSONParser.track(from: Data(thaiWhisperJSON.utf8))
        XCTAssertEqual(track.language, "th")
        XCTAssertEqual(track.cues.count, 2)
        XCTAssertEqual(track.cues[0].text, "สวัสดีครับทุกคน")
        XCTAssertEqual(track.cues[0].range.start.seconds, 0)
        XCTAssertEqual(track.cues[0].range.end.seconds, 2.5)
        XCTAssertEqual(track.cues[1].range.start.seconds, 3.0)
    }

    func testWordTimingsFilterSpecialTokens() throws {
        let track = try WhisperJSONParser.track(from: Data(thaiWhisperJSON.utf8))
        let words = track.cues[0].words
        XCTAssertEqual(words.map(\.text), ["สวัสดี", "ครับ", "ทุกคน"],
                       "[_BEG_]/[_TT_*] control tokens must be dropped")
        XCTAssertEqual(words[0].range.start.seconds, 0)
        XCTAssertEqual(words[0].range.end.seconds, 0.9)
        XCTAssertEqual(words[2].range.end.seconds, 2.5)
    }

    func testMillisecondPrecisionExact() throws {
        let track = try WhisperJSONParser.track(from: Data(thaiWhisperJSON.utf8))
        // 900 ms must be exactly 9/10 s in rational time, not a float artifact.
        XCTAssertEqual(track.cues[0].words[0].range.end,
                       RationalTime(value: 900, timescale: 1000))
    }

    func testLanguageHintUsedWhenJSONOmitsLanguage() throws {
        let json = """
        { "transcription": [ { "offsets": { "from": 0, "to": 1000 }, "text": "hello" } ] }
        """
        let track = try WhisperJSONParser.track(from: Data(json.utf8), languageHint: "th")
        XCTAssertEqual(track.language, "th")
    }

    func testRejectsMalformedAndEmpty() {
        XCTAssertThrowsError(try WhisperJSONParser.track(from: Data("not json".utf8)))
        XCTAssertThrowsError(try WhisperJSONParser.track(
            from: Data(#"{"transcription":[]}"#.utf8)))
        // Segment with empty text only → no cues → error.
        XCTAssertThrowsError(try WhisperJSONParser.track(
            from: Data(#"{"transcription":[{"offsets":{"from":0,"to":100},"text":"  "}]}"#.utf8)))
    }

    func testSpecialTokenDetection() {
        XCTAssertTrue(WhisperJSONParser.isSpecialToken("[_BEG_]"))
        XCTAssertTrue(WhisperJSONParser.isSpecialToken("[_TT_42]"))
        XCTAssertTrue(WhisperJSONParser.isSpecialToken("<|endoftext|>"))
        XCTAssertFalse(WhisperJSONParser.isSpecialToken("สวัสดี"))
        XCTAssertFalse(WhisperJSONParser.isSpecialToken("hello"))
    }

    // MARK: Parsed track flows into the caption pipeline

    func testWhisperTrackWrapsThaiCorrectly() throws {
        let track = try WhisperJSONParser.track(from: Data(thaiWhisperJSON.utf8))
        let wrapped = track.wrapped(maxCharactersPerLine: 8)
        for cue in wrapped.cues {
            XCTAssertLessThanOrEqual(cue.text.count, 8)
            XCTAssertFalse(cue.text.contains(" "), "Thai tokens must rejoin without spaces")
        }
        XCTAssertEqual(wrapped.cues.map(\.text).joined(),
                       "สวัสดีครับทุกคนวันนี้อากาศดีมาก")
    }

    // MARK: CLI wrapper

    func testCLIArgumentConstruction() {
        let transcriber = WhisperCLITranscriber(modelPath: "/models/ggml-large-v3.bin",
                                                runner: { _, _ in Data() })
        let args = transcriber.arguments(
            for: URL(fileURLWithPath: "/media/คลิปไทย.wav"), language: "th", jsonBase: "/tmp/out")
        XCTAssertTrue(args.contains("--output-json-full"))
        XCTAssertTrue(args.contains("-l") && args.contains("th"))
        XCTAssertTrue(args.contains("/models/ggml-large-v3.bin"))
        XCTAssertTrue(args.contains("/media/คลิปไทย.wav"))
        XCTAssertTrue(args.contains("--max-len"), "token-level timestamps required")
    }

    func testCLITranscribeUsesRunnerAndParses() async throws {
        let json = thaiWhisperJSON
        let transcriber = WhisperCLITranscriber(
            modelPath: "/models/m.bin",
            runner: { arguments, jsonPath in
                XCTAssertTrue(jsonPath.hasSuffix(".json"))
                XCTAssertTrue(arguments.contains("-l"))
                return Data(json.utf8)
            })
        let track = try await transcriber.transcribe(
            URL(fileURLWithPath: "/media/a.wav"), language: "th")
        XCTAssertEqual(track.language, "th")
        XCTAssertEqual(track.cues.count, 2)
    }

    func testCLITranscribeSurfacesRunnerFailure() async {
        let transcriber = WhisperCLITranscriber(
            modelPath: "/models/m.bin",
            runner: { _, _ in throw StudioError.io(path: "whisper-cli", detail: "not installed") })
        do {
            _ = try await transcriber.transcribe(URL(fileURLWithPath: "/a.wav"), language: nil)
            XCTFail("expected error")
        } catch let StudioError.io(path, _) {
            XCTAssertEqual(path, "whisper-cli")
        } catch {
            XCTFail("wrong error: \(error)")
        }
    }
}
