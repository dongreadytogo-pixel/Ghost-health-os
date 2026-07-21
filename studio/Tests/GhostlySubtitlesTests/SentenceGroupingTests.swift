import XCTest
import GhostlyCore
@testable import GhostlySubtitles

/// Thai sentence grouping (Workflow Constitution v5): word-fragment ASR cues
/// become natural sentence-sized subtitles.
final class SentenceGroupingTests: XCTestCase {
    private func cue(_ text: String, _ from: Double, _ to: Double,
                     speaker: String? = nil) -> SubtitleCue {
        SubtitleCue(range: TimeRange(start: RationalTime(seconds: from),
                                     end: RationalTime(seconds: to)),
                    text: text, speaker: speaker)
    }

    private func track(_ cues: [SubtitleCue]) -> SubtitleTrack {
        SubtitleTrack(language: "th", cues: cues)
    }

    func testGreetingStaysTogetherDespiteParticle() {
        // "สวัสดีครับทุกคน" — ครับ mid-greeting with no pause must not split.
        let grouped = track([
            cue("สวัสดี", 0.0, 0.9),
            cue("ครับ", 0.9, 1.5),
            cue("ทุกคน", 1.5, 2.5),
        ]).groupedIntoSentences()
        XCTAssertEqual(grouped.cues.map(\.text), ["สวัสดีครับทุกคน"])
        XCTAssertEqual(grouped.cues[0].range.start.seconds, 0)
        XCTAssertEqual(grouped.cues[0].range.end.seconds, 2.5)
    }

    func testParticlePlusShortPauseEndsSentence() {
        // "…ดีมากครับ" + 0.4 s breath + next sentence: 0.4 s alone is below
        // the 0.6 s pause threshold — the particle is what ends the sentence.
        let grouped = track([
            cue("วันนี้", 0.0, 0.5),
            cue("อากาศ", 0.5, 1.0),
            cue("ดีมาก", 1.0, 1.5),
            cue("ครับ", 1.5, 1.9),
            cue("เราไป", 2.3, 2.8),
            cue("เที่ยวกัน", 2.8, 3.4),
        ]).groupedIntoSentences()
        XCTAssertEqual(grouped.cues.map(\.text),
                       ["วันนี้อากาศดีมากครับ", "เราไปเที่ยวกัน"])
    }

    func testLongPauseSplitsWithoutParticle() {
        let grouped = track([
            cue("ไปกันเถอะ", 0.0, 1.0),
            cue("เดี๋ยวสาย", 2.0, 3.0), // 1.0 s gap
        ]).groupedIntoSentences()
        XCTAssertEqual(grouped.cues.count, 2)
    }

    func testCharacterCapSplitsRunOnSpeech() {
        // Continuous fragments with no pauses or particles: the cap splits.
        let fragments = (0..<12).map { i in
            cue("พูดต่อเนื่อง", Double(i) * 0.5, Double(i) * 0.5 + 0.5)
        }
        let grouped = track(fragments).groupedIntoSentences(maxCharactersPerCue: 40)
        XCTAssertGreaterThan(grouped.cues.count, 1)
        for c in grouped.cues {
            XCTAssertLessThanOrEqual(c.text.count, 40)
        }
        XCTAssertEqual(grouped.cues.map(\.text).joined(),
                       fragments.map(\.text).joined(), "no text lost")
    }

    func testSpeakerChangeAlwaysSplits() {
        let grouped = track([
            cue("สบายดีไหม", 0.0, 1.0, speaker: "S1"),
            cue("สบายดีมาก", 1.1, 2.0, speaker: "S2"),
        ]).groupedIntoSentences()
        XCTAssertEqual(grouped.cues.count, 2)
        XCTAssertEqual(grouped.cues.map(\.speaker), ["S1", "S2"])
    }

    func testMixedThaiEnglishJoinsWithSpaceWordTimingsSurvive() {
        var first = cue("ใช้กล้อง", 0.0, 0.8)
        first.words = [SubtitleCue.TimedWord(
            text: "ใช้กล้อง",
            range: TimeRange(start: RationalTime(seconds: 0),
                             end: RationalTime(seconds: 0.8)))]
        var second = cue("Sony A7", 0.9, 1.6)
        second.words = [SubtitleCue.TimedWord(
            text: "Sony A7",
            range: TimeRange(start: RationalTime(seconds: 0.9),
                             end: RationalTime(seconds: 1.6)))]
        let grouped = track([first, second]).groupedIntoSentences()
        XCTAssertEqual(grouped.cues.map(\.text), ["ใช้กล้อง Sony A7"])
        XCTAssertEqual(grouped.cues[0].words.count, 2, "word timings concatenate")
    }

    func testEnglishTerminalPunctuationEndsSentence() {
        XCTAssertTrue(SubtitleTrack.endsSentence("Let's go."))
        XCTAssertTrue(SubtitleTrack.endsSentence("จริงเหรอ?"))
        XCTAssertTrue(SubtitleTrack.endsSentence("ขอบคุณมากค่ะ"))
        XCTAssertFalse(SubtitleTrack.endsSentence("วันนี้"))
    }
}
