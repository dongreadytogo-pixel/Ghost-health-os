import XCTest
import GhostlyCore
import GhostlyDomain
@testable import GhostlySubtitles

final class SubtitleTests: XCTestCase {
    private let sampleSRT = """
    1
    00:00:01,000 --> 00:00:03,500
    Hello there!

    2
    00:00:04,000 --> 00:00:06,000
    NARRATOR: Welcome to the show.

    3
    00:00:06,200 --> 00:00:08,000
    Multi
    line cue
    """

    // MARK: SRT

    func testParseSRT() throws {
        let track = try SRT.parse(sampleSRT)
        XCTAssertEqual(track.cues.count, 3)
        XCTAssertEqual(track.cues[0].text, "Hello there!")
        XCTAssertEqual(track.cues[0].range.start.seconds, 1.0)
        XCTAssertEqual(track.cues[0].range.end.seconds, 3.5)
        XCTAssertEqual(track.cues[1].speaker, "NARRATOR")
        XCTAssertEqual(track.cues[1].text, "Welcome to the show.")
        XCTAssertEqual(track.cues[2].text, "Multi\nline cue")
    }

    func testParseSRTToleratesCRLFAndBOM() throws {
        let crlf = "\u{FEFF}" + sampleSRT.replacingOccurrences(of: "\n", with: "\r\n")
        let track = try SRT.parse(crlf)
        XCTAssertEqual(track.cues.count, 3)
    }

    func testParseSRTRejectsGarbage() {
        XCTAssertThrowsError(try SRT.parse("no cues here"))
        XCTAssertThrowsError(try SRT.parse("1\n00:00:02,000 --> 00:00:01,000\nBackwards"))
    }

    func testSRTRoundTrip() throws {
        let track = try SRT.parse(sampleSRT)
        let reparsed = try SRT.parse(SRT.serialize(track))
        XCTAssertEqual(reparsed.cues, track.cues)
    }

    func testTimestampFormatting() {
        XCTAssertEqual(SRT.timestamp(RationalTime(value: 3_723_456, timescale: 1000)),
                       "01:02:03,456")
        XCTAssertEqual(SRT.timestamp(.zero), "00:00:00,000")
    }

    func testTimestampParsingRejectsInvalid() {
        XCTAssertNil(SRT.parseTimestamp("00:00:01"))       // no millis
        XCTAssertNil(SRT.parseTimestamp("00:61:00,000"))    // bad minutes
        XCTAssertNil(SRT.parseTimestamp("xx:00:00,000"))
        XCTAssertNil(SRT.parseTimestamp("00:00:00,1000"))
    }

    // MARK: WebVTT

    func testParseVTT() throws {
        let vtt = """
        WEBVTT

        00:01.000 --> 00:03.000
        Hello <b>bold</b> world

        00:00:04.000 --> 00:00:05.000 align:center
        Second cue
        """
        let track = try WebVTT.parse(vtt)
        XCTAssertEqual(track.cues.count, 2)
        XCTAssertEqual(track.cues[0].text, "Hello bold world", "markup must be stripped")
        XCTAssertEqual(track.cues[0].range.start.seconds, 1.0)
        XCTAssertEqual(track.cues[1].range.start.seconds, 4.0)
    }

    func testVTTRequiresHeader() {
        XCTAssertThrowsError(try WebVTT.parse("1\n00:00:01,000 --> 00:00:02,000\nX"))
    }

    func testVTTSerializeRoundTrip() throws {
        let track = try SRT.parse(sampleSRT)
        let vtt = WebVTT.serialize(track)
        XCTAssertTrue(vtt.hasPrefix("WEBVTT"))
        let reparsed = try WebVTT.parse(vtt)
        XCTAssertEqual(reparsed.cues.count, track.cues.count)
        XCTAssertEqual(reparsed.cues[0].range, track.cues[0].range)
    }

    // MARK: Track operations

    private func wordCue(_ words: [(String, Double, Double)]) -> SubtitleCue {
        let timed = words.map { word in
            SubtitleCue.TimedWord(text: word.0, range: TimeRange(
                start: RationalTime(seconds: word.1, preferredTimescale: 1000),
                end: RationalTime(seconds: word.2, preferredTimescale: 1000)))
        }
        return SubtitleCue(
            range: TimeRange(start: timed.first!.range.start, end: timed.last!.range.end),
            text: words.map(\.0).joined(separator: " "),
            words: timed)
    }

    func testWrappedSplitsOnWordBoundaries() {
        let cue = wordCue([("The", 0, 0.2), ("quick", 0.2, 0.5), ("brown", 0.5, 0.9),
                           ("fox", 0.9, 1.2), ("jumps", 1.2, 1.6)])
        let track = SubtitleTrack(cues: [cue]).wrapped(maxCharactersPerLine: 11)
        XCTAssertGreaterThan(track.cues.count, 1)
        for wrapped in track.cues {
            XCTAssertLessThanOrEqual(wrapped.text.count, 11)
        }
        // Timing must be preserved end-to-end.
        XCTAssertEqual(track.cues.first?.range.start, cue.range.start)
        XCTAssertEqual(track.cues.last?.range.end, cue.range.end)
        // No words lost.
        XCTAssertEqual(track.cues.flatMap(\.words).map(\.text),
                       ["The", "quick", "brown", "fox", "jumps"])
    }

    func testShifted() throws {
        let track = try SRT.parse(sampleSRT).shifted(by: RationalTime(seconds: 10))
        XCTAssertEqual(track.cues[0].range.start.seconds, 11.0)
        XCTAssertEqual(track.cues[0].range.duration.seconds, 2.5, accuracy: 1e-9)
    }

    func testCaptionBridge() throws {
        let track = try SRT.parse(sampleSRT)
        let captions = track.captions(format: .itt, styleName: "YouTube")
        XCTAssertEqual(captions.count, 3)
        XCTAssertEqual(captions[1].text, "NARRATOR: Welcome to the show.")
        XCTAssertEqual(captions[0].format, .itt)
        XCTAssertEqual(captions[0].styleName, "YouTube")
    }

    // MARK: Styles

    func testBuiltInStylesLookup() {
        XCTAssertNotNil(CaptionStyle.named("tiktok"))
        XCTAssertNotNil(CaptionStyle.named("YouTube"))
        XCTAssertNil(CaptionStyle.named("mystery"))
        XCTAssertEqual(CaptionStyle.builtIn.count, 4)
    }

    func testTikTokStyleTransformsTrack() {
        let cue = wordCue([("hello", 0, 0.4), ("wonderful", 0.4, 1.0), ("world", 1.0, 1.4),
                           ("of", 1.4, 1.6), ("video", 1.6, 2.0)])
        let styled = CaptionStyle.tiktok.styled(SubtitleTrack(cues: [cue]))
        for c in styled.cues {
            XCTAssertEqual(c.text, c.text.uppercased())
            XCTAssertLessThanOrEqual(c.text.count, CaptionStyle.tiktok.maxCharactersPerLine)
        }
    }

    func testColorClampingAndFCPXMLString() {
        let color = CaptionStyle.ColorValue(red: 2, green: -1, blue: 0.5, alpha: 0.7)
        XCTAssertEqual(color.red, 1)
        XCTAssertEqual(color.green, 0)
        XCTAssertEqual(color.fcpxml, "1 0 0.5 0.7")
    }

    func testStyleCodableRoundTrip() throws {
        let data = try JSONEncoder().encode(CaptionStyle.tiktok)
        let decoded = try JSONDecoder().decode(CaptionStyle.self, from: data)
        XCTAssertEqual(decoded, CaptionStyle.tiktok)
    }
}
