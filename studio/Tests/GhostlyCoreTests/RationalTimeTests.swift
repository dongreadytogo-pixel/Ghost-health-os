import XCTest
@testable import GhostlyCore

final class RationalTimeTests: XCTestCase {
    func testReducesToLowestTerms() {
        let t = RationalTime(value: 3000, timescale: 6000)
        XCTAssertEqual(t.value, 1)
        XCTAssertEqual(t.timescale, 2)
    }

    func testAdditionAcrossTimescales() {
        let a = RationalTime(value: 1001, timescale: 30_000) // one 29.97 frame
        let b = RationalTime(value: 1, timescale: 25)        // one PAL frame
        let sum = a + b
        XCTAssertEqual(sum.seconds, 1001.0 / 30_000.0 + 0.04, accuracy: 1e-12)
    }

    func testSubtractionCanGoNegative() {
        let a = RationalTime(seconds: 1)
        let b = RationalTime(seconds: 3)
        XCTAssertTrue((a - b).isNegative)
        XCTAssertEqual((a - b).seconds, -2, accuracy: 1e-12)
    }

    func testExactAccumulationDoesNotDrift() {
        // 10 000 NTSC frames accumulated exactly.
        let frame = FrameRate.fps29_97.frameDuration
        var total = RationalTime.zero
        for _ in 0..<10_000 { total = total + frame }
        XCTAssertEqual(total, RationalTime(value: 1001 * 10_000, timescale: 30_000))
    }

    func testFCPXMLStringRoundTrip() {
        for s in ["0s", "5s", "3003/3000s", "-1001/30000s"] {
            let t = RationalTime(fcpxml: s)
            XCTAssertNotNil(t, s)
            XCTAssertEqual(RationalTime(fcpxml: t!.description), t, s)
        }
    }

    func testFCPXMLStringRejectsGarbage() {
        XCTAssertNil(RationalTime(fcpxml: "5"))
        XCTAssertNil(RationalTime(fcpxml: "s"))
        XCTAssertNil(RationalTime(fcpxml: "a/bs"))
        XCTAssertNil(RationalTime(fcpxml: "1/0s"))
        XCTAssertNil(RationalTime(fcpxml: ""))
    }

    func testComparable() {
        XCTAssertLessThan(RationalTime(value: 1, timescale: 30), RationalTime(value: 1, timescale: 25))
        XCTAssertGreaterThan(RationalTime(seconds: 2), RationalTime(value: 59, timescale: 30))
    }

    func testScaled() {
        // Retime 10s to 50% speed → 20s.
        let t = RationalTime(seconds: 10).scaled(by: 2, over: 1)
        XCTAssertEqual(t.seconds, 20, accuracy: 1e-12)
        let half = RationalTime(seconds: 10).scaled(by: 1, over: 2)
        XCTAssertEqual(half.seconds, 5, accuracy: 1e-12)
    }

    func testTimeRangeOverlapAndIntersection() {
        let a = TimeRange(start: RationalTime(seconds: 0), duration: RationalTime(seconds: 5))
        let b = TimeRange(start: RationalTime(seconds: 4), duration: RationalTime(seconds: 5))
        let c = TimeRange(start: RationalTime(seconds: 5), duration: RationalTime(seconds: 1))
        XCTAssertTrue(a.overlaps(b))
        XCTAssertFalse(a.overlaps(c), "half-open ranges: [0,5) does not overlap [5,6)")
        let i = a.intersection(b)
        XCTAssertEqual(i?.start.seconds, 4)
        XCTAssertEqual(i?.duration.seconds, 1)
        XCTAssertNil(a.intersection(c))
    }

    func testFrameSnapping() {
        let rate = FrameRate.fps29_97
        let t = RationalTime(seconds: 1.0) // not on a 29.97 boundary
        let snapped = rate.snapped(t)
        XCTAssertLessThanOrEqual(snapped, t)
        // Snapped value must be an integer number of frames.
        let frames = snapped.seconds / rate.frameDuration.seconds
        XCTAssertEqual(frames, frames.rounded(), accuracy: 1e-9)
    }

    func testFrameRateNominalFPS() {
        XCTAssertEqual(FrameRate.fps23_976.nominalFPS, 23.976, accuracy: 0.001)
        XCTAssertEqual(FrameRate.fps60.nominalFPS, 60)
    }
}
