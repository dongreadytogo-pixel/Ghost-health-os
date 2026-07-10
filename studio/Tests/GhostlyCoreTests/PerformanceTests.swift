import XCTest
import GhostlyCore

/// Phase 17 baselines: hot-path timing math. `measure` blocks record
/// timings without failing (no stored baselines on CI), so they document
/// throughput and catch pathological regressions during local profiling.
final class CorePerformanceTests: XCTestCase {
    func testRationalTimeAccumulationPerformance() {
        // A long timeline assembled clip by clip: 100k exact additions
        // across mixed timescales must stay exact and fast (no drift, no
        // denominator blow-up thanks to lowest-terms reduction).
        let deltas = [
            RationalTime(value: 1001, timescale: 30_000),
            RationalTime(value: 1, timescale: 25),
            RationalTime(value: 1, timescale: 48_000),
        ]
        measure {
            var total = RationalTime.zero
            for i in 0..<100_000 {
                total = total + deltas[i % deltas.count]
            }
            XCTAssertGreaterThan(total.seconds, 0)
        }
    }

    func testFrameSnappingPerformance() {
        let rate = FrameRate.fps29_97
        measure {
            var accumulated = 0.0
            for i in 0..<50_000 {
                let t = RationalTime(value: Int64(i * 333), timescale: 10_000)
                accumulated += rate.snapped(t).seconds
            }
            XCTAssertGreaterThan(accumulated, 0)
        }
    }
}
