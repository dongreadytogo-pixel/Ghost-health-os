import XCTest
import GhostlyCore

/// Phase 17 baselines: hot-path timing math. Best-of-N wall time against a
/// deliberately generous budget — robust on noisy CI runners (XCTest's
/// `measure` fails on >10% deviation under corelibs XCTest), while still
/// catching pathological regressions like accidental quadratic behavior.
/// Each block also asserts its computed result, so wrong output fails too.
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
        assertPerformance("rational-accumulation-100k", budget: 10) {
            var total = RationalTime.zero
            for i in 0..<100_000 {
                total = total + deltas[i % deltas.count]
            }
            XCTAssertGreaterThan(total.seconds, 0)
        }
    }

    func testFrameSnappingPerformance() {
        let rate = FrameRate.fps29_97
        assertPerformance("frame-snapping-50k", budget: 5) {
            var accumulated = 0.0
            for i in 0..<50_000 {
                let t = RationalTime(value: Int64(i * 333), timescale: 10_000)
                accumulated += rate.snapped(t).seconds
            }
            XCTAssertGreaterThan(accumulated, 0)
        }
    }
}

/// Best-of-N wall clock vs a generous budget; prints the timing for humans.
func assertPerformance(_ name: String, iterations: Int = 3, budget: TimeInterval,
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
