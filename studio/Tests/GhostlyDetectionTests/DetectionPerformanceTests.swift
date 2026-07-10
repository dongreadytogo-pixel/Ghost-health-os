import XCTest
import GhostlyCore
@testable import GhostlyDetection

/// Phase 17 baselines: detector throughput on minutes of audio. The blocks
/// record timings (no stored baselines on CI) and assert the results stay
/// sane, so a pathological slowdown or wrong output both surface.
final class DetectionPerformanceTests: XCTestCase {
    /// 60 s of narration-shaped audio at 16 kHz (960k samples).
    private static let longNarration: [Float] = {
        var fixture = AudioFixture(sampleRate: 16_000)
        for _ in 0..<10 {
            fixture = fixture.speech(4.0).silence(2.0)
        }
        return fixture.samples()
    }()

    func testSilenceDetectorThroughput() {
        let samples = Self.longNarration
        measure {
            let ranges = SilenceDetector().speechRanges(samples: samples, sampleRate: 16_000)
            XCTAssertEqual(ranges.count, 10)
        }
    }

    func testBeatDetectorThroughput() {
        let samples = AudioFixture(sampleRate: 16_000).beats(bpm: 128, seconds: 60).samples()
        measure {
            let result = BeatDetector().detect(samples: samples, sampleRate: 16_000)
            XCTAssertGreaterThan(result.beats.count, 60)
        }
    }

    func testWAVDecodeThroughput() throws {
        let data = AudioFixture(sampleRate: 16_000).noise(60, seed: 5).wavData()
        measure {
            let audio = try? WAV.decode(data)
            XCTAssertEqual(audio?.samples.count, 960_000)
        }
    }
}
