import XCTest
import GhostlyCore
@testable import GhostlyDetection

/// Multicam sync (ซิงก์มุมกล้อง): recovering how much later/earlier each
/// camera started from audio alone.
final class AudioAlignerTests: XCTestCase {
    private func scene(lead: Double) -> WAV.Audio {
        AudioFixture(sampleRate: 16_000)
            .silence(lead)
            .silence(0.6).speech(1.8)
            .silence(0.4).speech(2.6)
            .silence(0.7).speech(1.2)
            .silence(0.5)
            .audio()
    }

    func testIdenticalRecordingsAlignAtZero() {
        let a = scene(lead: 0)
        XCTAssertEqual(AudioAligner().offsetSeconds(reference: a, other: a), 0,
                       accuracy: 0.02)
    }

    func testExtraLeadingSilenceMeansCameraStartedEarlier() {
        // `other` holds the same scene 2 s later in its file → that camera
        // started rolling 2 s BEFORE the reference → offset −2.
        let reference = scene(lead: 0)
        let other = scene(lead: 2)
        XCTAssertEqual(AudioAligner().offsetSeconds(reference: reference, other: other),
                       -2, accuracy: 0.05)
        // And symmetrically the reference started 2 s later than `other`.
        XCTAssertEqual(AudioAligner().offsetSeconds(reference: other, other: reference),
                       2, accuracy: 0.05)
    }

    func testFractionalOffsetAndLevelDifference() {
        let reference = scene(lead: 0)
        var quiet = scene(lead: 1.3)
        // A camera further from the subject records the same scene quieter.
        quiet = WAV.Audio(samples: quiet.samples.map { $0 * 0.3 },
                          sampleRate: quiet.sampleRate)
        XCTAssertEqual(AudioAligner().offsetSeconds(reference: reference, other: quiet),
                       -1.3, accuracy: 0.05,
                       "level differences must not shift the alignment")
    }

    func testEmptyAudioIsSafe() {
        let empty = WAV.Audio(samples: [], sampleRate: 16_000)
        XCTAssertEqual(AudioAligner().offsetSeconds(reference: empty, other: empty), 0)
    }
}
