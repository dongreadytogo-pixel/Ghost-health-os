import XCTest
import GhostlyCore
@testable import GhostlyDetection

final class FrameHistogramTests: XCTestCase {
    func testEmptyInputYieldsAllZeroHistogram() {
        let h = LumaHistogram.normalized(luma: [], bins: 8)
        XCTAssertEqual(h.count, 8)
        XCTAssertEqual(h.reduce(0, +), 0)
    }

    func testNormalizedSumsToOne() {
        let h = LumaHistogram.normalized(luma: [0.1, 0.4, 0.6, 0.9, 0.95], bins: 16)
        XCTAssertEqual(h.reduce(0, +), 1.0, accuracy: 1e-9)
    }

    func testBinPlacement() {
        // Values 0.0 and 1.0 must land in first and last bins respectively.
        let h = LumaHistogram.normalized(luma: [0.0, 1.0], bins: 4)
        XCTAssertEqual(h[0], 0.5, accuracy: 1e-9)
        XCTAssertEqual(h[3], 0.5, accuracy: 1e-9)
        XCTAssertEqual(h[1], 0)
        XCTAssertEqual(h[2], 0)
    }

    func testClampsOutOfRange() {
        let h = LumaHistogram.normalized(luma: [-1.0, 2.0], bins: 4)
        XCTAssertEqual(h[0], 0.5, accuracy: 1e-9, "negative clamps into first bin")
        XCTAssertEqual(h[3], 0.5, accuracy: 1e-9, "over-1 clamps into last bin")
    }

    func testGrayscaleConvenience() {
        let h = LumaHistogram.normalized(grayscale: [0, 255, 128, 128], bins: 4)
        XCTAssertEqual(h.reduce(0, +), 1.0, accuracy: 1e-9)
        XCTAssertEqual(h[0], 0.25, accuracy: 1e-9)  // 0 → bin 0
        XCTAssertEqual(h[3], 0.25, accuracy: 1e-9)  // 255 → bin 3
        XCTAssertEqual(h[2], 0.5, accuracy: 1e-9)   // two mid values → bin 2
    }

    func testRGBLumaWeighting() {
        // Pure green is brightest under Rec.601 (0.587), pure blue darkest.
        let green = LumaHistogram.normalizedRGB([0, 255, 0], bins: 10)
        let blue = LumaHistogram.normalizedRGB([0, 0, 255], bins: 10)
        let greenBin = green.firstIndex { $0 > 0 }!
        let blueBin = blue.firstIndex { $0 > 0 }!
        XCTAssertGreaterThan(greenBin, blueBin)
    }

    func testHistogramsFeedSceneDetector() {
        // Two distinct luma populations → a large histogram distance → a cut.
        let dark = LumaHistogram.normalized(luma: Array(repeating: 0.1, count: 100))
        let bright = LumaHistogram.normalized(luma: Array(repeating: 0.9, count: 100))
        let histograms = [dark, dark, bright, bright]
        let times = (0..<4).map { RationalTime(value: Int64($0), timescale: 5) }
        let cuts = SceneChangeDetector(threshold: 0.5, minimumSceneDuration: 0)
            .cuts(histograms: histograms, frameTimes: times)
        XCTAssertEqual(cuts, [RationalTime(value: 2, timescale: 5)])
    }
}
