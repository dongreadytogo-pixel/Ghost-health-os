import XCTest
import GhostlyCore
import GhostlyDomain
@testable import GhostlySubtitles

/// Thai is a primary target language (see docs/knowledge/CONSTITUTION.md).
/// Thai has no spaces between words, so wrapping and token-joining must be
/// script-aware and must never corrupt the text.
final class ThaiSubtitleTests: XCTestCase {
    private func time(_ s: Double) -> RationalTime { RationalTime(seconds: s, preferredTimescale: 1000) }

    // MARK: Script detection

    func testScriptDetection() {
        XCTAssertTrue(TextScript.isSpaceless("สวัสดีครับ"))
        XCTAssertTrue(TextScript.isSpaceless("こんにちは"))
        XCTAssertTrue(TextScript.isSpaceless("你好世界"))
        XCTAssertFalse(TextScript.isSpaceless("hello world"))
        XCTAssertTrue(TextScript.hasLatinLetters("hello"))
        XCTAssertFalse(TextScript.hasLatinLetters("สวัสดี"))
        // Mixed Thai + Latin still counts as having Latin letters.
        XCTAssertTrue(TextScript.hasLatinLetters("ยี่ห้อ Apple"))
    }

    // MARK: Character-based wrapping (no word timings)

    // MARK: Syllable-boundary segmentation (dictionary-free)

    func testBreakUnitsFollowThaiSyllableStructure() {
        XCTAssertEqual(ThaiSegmentation.breakUnits("สวัสดี"), ["ส", "วัส", "ดี"])
        XCTAssertEqual(ThaiSegmentation.breakUnits("อากาศ"), ["อา", "กาศ"])
        XCTAssertEqual(ThaiSegmentation.breakUnits("วันนี้อากาศดีมาก"),
                       ["วัน", "นี้", "อา", "กาศ", "ดี", "มาก"])
        // Leading vowel เ binds to its syllable; never a dangling "เ".
        XCTAssertEqual(ThaiSegmentation.breakUnits("เที่ยว"), ["เที่ยว"])
        // Digits travel as one unit between Thai runs.
        XCTAssertEqual(ThaiSegmentation.breakUnits("ราคา1500บาท"),
                       ["รา", "คา", "1500", "บาท"])
    }

    func testBreakUnitsJoinBackExactly() {
        for text in ["สวัสดีครับวันนี้เราจะมารีวิวกล้องตัวใหม่",
                     "ใครสนใจอย่าลืมกดติดตามช่องของเราด้วยนะครับ",
                     "ไปเที่ยวทะเลกันเถอะ", "๑๒๓ กับ abc"] {
            XCTAssertEqual(ThaiSegmentation.breakUnits(text).joined(), text)
        }
    }

    func testThaiWrapBreaksAtSyllableBoundaries() {
        let thai = "วันนี้อากาศดีมาก"
        let cue = SubtitleCue(range: TimeRange(start: time(0), end: time(4)), text: thai)
        let wrapped = SubtitleTrack(language: "th", cues: [cue]).wrapped(maxCharactersPerLine: 4)
        XCTAssertEqual(wrapped.cues.map(\.text).joined(), thai)
        let units = Set(ThaiSegmentation.breakUnits(thai))
        for c in wrapped.cues {
            XCTAssertLessThanOrEqual(c.text.count, 4)
            // Every line must itself be a join of whole syllable units —
            // no line may start or end mid-syllable.
            XCTAssertEqual(ThaiSegmentation.breakUnits(c.text).filter { !units.contains($0) },
                           [], "line '\(c.text)' broke inside a syllable")
        }
    }

    func testThaiWrapByCharacterPreservesText() throws {
        // A long Thai sentence with no spaces and no word timings.
        let thai = "สวัสดีครับวันนี้อากาศดีมากเราจะไปเที่ยวทะเลกันนะครับ" // 51 chars
        let cue = SubtitleCue(range: TimeRange(start: time(0), end: time(10)), text: thai)
        let wrapped = SubtitleTrack(language: "th", cues: [cue]).wrapped(maxCharactersPerLine: 15)

        XCTAssertGreaterThan(wrapped.cues.count, 1, "long Thai text must be split")
        for c in wrapped.cues {
            XCTAssertLessThanOrEqual(c.text.count, 15)
        }
        // Concatenating the pieces must reproduce the original exactly — no
        // characters dropped, no spurious spaces inserted.
        XCTAssertEqual(wrapped.cues.map(\.text).joined(), thai)
        // Time is partitioned contiguously across the original range.
        XCTAssertEqual(wrapped.cues.first?.range.start, time(0))
        let lastEnd = try XCTUnwrap(wrapped.cues.last).range.end.seconds
        XCTAssertEqual(lastEnd, 10, accuracy: 1e-6)
        for (a, b) in zip(wrapped.cues, wrapped.cues.dropFirst()) {
            XCTAssertEqual(a.range.end, b.range.start, "slices must be contiguous")
        }
    }

    // MARK: Word-timed wrapping rejoins Thai without spaces

    func testThaiTimedTokensRejoinWithoutSpaces() {
        // Whisper-style per-token timings for "สวัสดีตอนเช้า".
        func w(_ t: String, _ s: Double, _ e: Double) -> SubtitleCue.TimedWord {
            SubtitleCue.TimedWord(text: t, range: TimeRange(start: time(s), end: time(e)))
        }
        let words = [w("สวัสดี", 0, 0.5), w("ตอน", 0.5, 0.8), w("เช้า", 0.8, 1.2),
                     w("อากาศ", 1.2, 1.6), w("ดี", 1.6, 1.9)]
        let cue = SubtitleCue(range: TimeRange(start: time(0), end: time(1.9)),
                              text: words.map(\.text).joined(), words: words)
        let wrapped = SubtitleTrack(language: "th", cues: [cue]).wrapped(maxCharactersPerLine: 9)
        XCTAssertGreaterThan(wrapped.cues.count, 1)
        for c in wrapped.cues {
            XCTAssertFalse(c.text.contains(" "), "Thai tokens must rejoin without spaces: '\(c.text)'")
        }
        XCTAssertEqual(wrapped.cues.map(\.text).joined(), "สวัสดีตอนเช้าอากาศดี")
    }

    func testEnglishStillWrapsWithSpaces() {
        func w(_ t: String, _ s: Double, _ e: Double) -> SubtitleCue.TimedWord {
            SubtitleCue.TimedWord(text: t, range: TimeRange(start: time(s), end: time(e)))
        }
        let words = [w("the", 0, 0.2), w("quick", 0.2, 0.5), w("brown", 0.5, 0.8),
                     w("fox", 0.8, 1.0)]
        let cue = SubtitleCue(range: TimeRange(start: time(0), end: time(1.0)),
                              text: "the quick brown fox", words: words)
        let wrapped = SubtitleTrack(cues: [cue]).wrapped(maxCharactersPerLine: 10)
        XCTAssertTrue(wrapped.cues.contains { $0.text.contains(" ") },
                      "spaced languages keep their spaces")
    }

    // MARK: Caption language → FCPXML role

    func testThaiCaptionsCarryLanguage() {
        let track = SubtitleTrack(language: "th", cues: [
            SubtitleCue(range: TimeRange(start: time(0), end: time(2)), text: "สวัสดีครับ"),
        ])
        let captions = track.captions()
        XCTAssertEqual(captions.first?.language, "th")
        XCTAssertEqual(captions.first?.text, "สวัสดีครับ")
    }

    // MARK: AutoPunctuator leaves Thai alone

    func testAutoPunctuatorLeavesThaiUntouched() {
        let thai = "สวัสดีครับผมชื่อสมชาย"
        XCTAssertEqual(AutoPunctuator().punctuate(thai), thai,
                       "Thai must not get Latin capitalization or a trailing period")
    }

    func testAutoPunctuatorStillWorksOnEnglish() {
        XCTAssertEqual(AutoPunctuator().punctuate("how are you"), "How are you?")
    }
}
