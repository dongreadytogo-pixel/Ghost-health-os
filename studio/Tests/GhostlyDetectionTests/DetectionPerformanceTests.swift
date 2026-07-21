import XCTest
import GhostlyCore
@testable import GhostlyDetection

/// Phase 17 baselines: detector throughput on minutes of audio. Best-of-N
/// wall time against generous budgets (see CorePerformanceTests for why
/// XCTest `measure` is unsuitable on CI), with correctness asserted inside
/// each block.
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
        assertDetectionPerformance("silence-60s", budget: 5) {
            let ranges = SilenceDetector().speechRanges(samples: samples, sampleRate: 16_000)
            XCTAssertEqual(ranges.count, 10)
        }
    }

    func testBeatDetectorThroughput() {
        let samples = AudioFixture(sampleRate: 16_000).beats(bpm: 128, seconds: 60).samples()
        assertDetectionPerformance("beats-60s", budget: 5) {
            let result = BeatDetector().detect(samples: samples, sampleRate: 16_000)
            XCTAssertGreaterThan(result.beats.count, 60)
        }
    }

    func testWAVDecodeThroughput() throws {
        let data = AudioFixture(sampleRate: 16_000).noise(60, seed: 5).wavData()
        assertDetectionPerformance("wav-decode-60s", budget: 5) {
            let audio = try? WAV.decode(data)
            XCTAssertEqual(audio?.samples.count, 960_000)
        }
    }
}

/// Best-of-N wall clock vs a generous budget; prints the timing for humans.
private func assertDetectionPerformance(
    _ name: String, iterations: Int = 3, budget: TimeInterval,
    file: StaticString = #filePath, line: UInt = #line,
    _ block: () throws -> Void) rethrows {
    var best = Double.greatestFiniteMagnitude
    for _ in 0..<iterations {
        let start = DispatchTime.now().uptimeNanoseconds
        try block()
        let elapsed = Double(DispatchTime.now().uptimeNanoseconds - start) / 1e9
        best = min(best, elapsed)
    }
    print("perf[\(name)]: best \(String(format: "%.3f", best))s of \(iterations) runs (budget \(budget)s)")
    XCTAssertLessThan(best, budget, "\(name) blew its performance budget",
                      file: file, line: line)
}
