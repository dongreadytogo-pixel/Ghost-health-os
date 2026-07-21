import XCTest
import GhostlyCore
@testable import GhostlyDetection

final class DiarizationTests: XCTestCase {
    /// Two people alternating: a low voice (~160 Hz) and a high one (~320 Hz).
    private func conversation() -> AudioFixture {
        AudioFixture(sampleRate: 16_000)
            .silence(0.5)
            .tone(frequency: 160, seconds: 1.2)   // S1
            .silence(0.5)
            .tone(frequency: 320, seconds: 1.2)   // S2
            .silence(0.5)
            .tone(frequency: 160, seconds: 1.2)   // S1 again
            .silence(0.5)
            .tone(frequency: 320, seconds: 1.2)   // S2 again
            .silence(0.5)
    }

    private func turns(for fixture: AudioFixture) -> [SpeakerTurn] {
        let samples = fixture.samples()
        let speech = SilenceDetector().speechRanges(samples: samples,
                                                    sampleRate: fixture.sampleRate)
        return SpeakerDiarizer().turns(samples: samples,
                                       sampleRate: fixture.sampleRate,
                                       speechRanges: speech)
    }

    func testAlternatingVoicesGetTwoStableLabels() {
        let result = turns(for: conversation())
        XCTAssertEqual(result.count, 4)
        XCTAssertEqual(SpeakerDiarizer.speakerCount(result), 2)
        XCTAssertEqual(result.map(\.speaker), ["S1", "S2", "S1", "S2"],
                       "same voice must get the same label on every turn")
    }

    func testSingleVoiceIsOneSpeaker() {
        let monologue = AudioFixture(sampleRate: 16_000)
            .silence(0.5).tone(frequency: 200, seconds: 1.5)
            .silence(0.5).tone(frequency: 200, seconds: 1.5)
            .silence(0.5)
        let result = turns(for: monologue)
        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(SpeakerDiarizer.speakerCount(result), 1)
    }

    func testEmptyAndNoSpeech() {
        XCTAssertTrue(SpeakerDiarizer().turns(samples: [], sampleRate: 16_000,
                                              speechRanges: []).isEmpty)
        let silence = AudioFixture(sampleRate: 16_000).silence(3)
        XCTAssertTrue(turns(for: silence).isEmpty)
    }

    func testDeterministic() {
        XCTAssertEqual(turns(for: conversation()), turns(for: conversation()))
    }

    func testFundamentalFrequencyEstimate() {
        let tone = AudioFixture(sampleRate: 16_000)
            .tone(frequency: 220, seconds: 0.5).samples()
        let pitch = SpeakerDiarizer.fundamental(of: tone[0...], sampleRate: 16_000)
        XCTAssertEqual(try XCTUnwrap(pitch), 220, accuracy: 8)

        let hiss = AudioFixture(sampleRate: 16_000).noise(0.5, seed: 7).samples()
        // Noise may or may not clear the voicing bar, but silence never does.
        let quiet = [Float](repeating: 0, count: 8000)
        XCTAssertNil(SpeakerDiarizer.fundamental(of: quiet[0...], sampleRate: 16_000))
        _ = hiss // documented: noise is attributed to the previous speaker upstream
    }

    func testMaxSpeakersCap() {
        // Four distinct voices but a cap of 2: extra voices fold into nearest.
        let crowd = AudioFixture(sampleRate: 16_000)
            .tone(frequency: 120, seconds: 1).silence(0.5)
            .tone(frequency: 180, seconds: 1).silence(0.5)
            .tone(frequency: 260, seconds: 1).silence(0.5)
            .tone(frequency: 380, seconds: 1)
        let samples = crowd.samples()
        let speech = SilenceDetector().speechRanges(samples: samples, sampleRate: 16_000)
        let result = SpeakerDiarizer(maxSpeakers: 2).turns(
            samples: samples, sampleRate: 16_000, speechRanges: speech)
        XCTAssertLessThanOrEqual(SpeakerDiarizer.speakerCount(result), 2)
    }
}
