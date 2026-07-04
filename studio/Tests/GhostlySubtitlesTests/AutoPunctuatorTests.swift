import XCTest
import GhostlyCore
@testable import GhostlySubtitles

final class AutoPunctuatorTests: XCTestCase {
    func testCapitalizesSentenceStart() {
        XCTAssertEqual(AutoPunctuator().punctuate("hello there"), "Hello there.")
    }

    func testCapitalizesPronounI() {
        XCTAssertEqual(AutoPunctuator().punctuate("yesterday i went home"),
                       "Yesterday I went home.")
    }

    func testAddsQuestionMarkForQuestionOpener() {
        XCTAssertEqual(AutoPunctuator().punctuate("how are you"), "How are you?")
        XCTAssertEqual(AutoPunctuator().punctuate("what is this"), "What is this?")
    }

    func testDoesNotDoublePunctuate() {
        XCTAssertEqual(AutoPunctuator().punctuate("Already done!"), "Already done!")
        XCTAssertEqual(AutoPunctuator().punctuate("Is it?"), "Is it?")
    }

    func testProperNouns() {
        let p = AutoPunctuator(properNouns: ["london", "sarah"])
        XCTAssertEqual(p.punctuate("i met sarah in london"), "I met Sarah in London.")
    }

    func testCapitalizesAfterMidSentenceTerminator() {
        XCTAssertEqual(AutoPunctuator().punctuate("stop. go now"), "Stop. Go now.")
    }

    func testEmptyAndWhitespacePreserved() {
        XCTAssertEqual(AutoPunctuator().punctuate(""), "")
        XCTAssertEqual(AutoPunctuator().punctuate("   "), "   ")
    }

    func testPunctuatesTrackPreservingTiming() {
        let cue = SubtitleCue(range: TimeRange(start: RationalTime(seconds: 1),
                                               duration: RationalTime(seconds: 2)),
                              text: "hello world")
        let track = SubtitleTrack(cues: [cue])
        let result = AutoPunctuator().punctuate(track)
        XCTAssertEqual(result.cues[0].text, "Hello world.")
        XCTAssertEqual(result.cues[0].range, cue.range, "timing must be untouched")
    }

    func testNeverRemovesText() {
        let input = "the quick brown fox jumps over the lazy dog"
        let output = AutoPunctuator().punctuate(input)
        // Every original word (lowercased) must still be present.
        for word in input.split(separator: " ") {
            XCTAssertTrue(output.lowercased().contains(word.lowercased()))
        }
    }
}
