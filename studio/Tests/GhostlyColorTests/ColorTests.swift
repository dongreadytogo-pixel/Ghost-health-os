import XCTest
import GhostlyCore
@testable import GhostlyColor

final class ColorTests: XCTestCase {
    // MARK: LUT structure

    func testIdentityLUTSamplesInput() throws {
        let lut = try CubeLUT.identity(size: 17)
        for probe in [RGB(0, 0, 0), RGB(1, 1, 1), RGB(0.5, 0.25, 0.75), RGB(0.18, 0.18, 0.18)] {
            let out = lut.sample(probe)
            XCTAssertEqual(out.r, probe.r, accuracy: 1e-9)
            XCTAssertEqual(out.g, probe.g, accuracy: 1e-9)
            XCTAssertEqual(out.b, probe.b, accuracy: 1e-9)
        }
    }

    func testRejectsBadSizeAndTable() {
        XCTAssertThrowsError(try CubeLUT(size: 1, table: [RGB(0, 0, 0)]))
        XCTAssertThrowsError(try CubeLUT(size: 2, table: [RGB(0, 0, 0)]),
                             "2³ = 8 entries required")
    }

    // MARK: .cube codec

    func testParseSerializeRoundTrip() throws {
        let original = try ColorAdjustments(exposureEV: 0.5, contrast: 1.2,
                                            saturation: 1.1, temperature: 0.2)
            .lut(size: 5, title: "อุ่นนิด ๆ (warm)")
        let reparsed = try CubeLUT.parse(original.serialized())
        XCTAssertEqual(reparsed.size, 5)
        XCTAssertEqual(reparsed.title, "อุ่นนิด ๆ (warm)")
        for (a, b) in zip(reparsed.table, original.table) {
            XCTAssertEqual(a.r, b.r, accuracy: 1e-5)
            XCTAssertEqual(a.g, b.g, accuracy: 1e-5)
            XCTAssertEqual(a.b, b.b, accuracy: 1e-5)
        }
    }

    func testParseAcceptsCommentsAndDomainLines() throws {
        let cube = """
        # Created by some tool
        TITLE "Tiny"
        DOMAIN_MIN 0.0 0.0 0.0
        DOMAIN_MAX 1.0 1.0 1.0
        LUT_3D_SIZE 2

        0 0 0
        1 0 0
        0 1 0
        1 1 0
        0 0 1
        1 0 1
        0 1 1
        1 1 1
        """
        let lut = try CubeLUT.parse(cube)
        XCTAssertEqual(lut.size, 2)
        XCTAssertEqual(lut.title, "Tiny")
        let mid = lut.sample(RGB(0.5, 0.5, 0.5))
        XCTAssertEqual(mid.r, 0.5, accuracy: 1e-9, "identity cube must interpolate linearly")
    }

    func testParseRejectsMalformed() {
        XCTAssertThrowsError(try CubeLUT.parse("not a lut"))
        XCTAssertThrowsError(try CubeLUT.parse("LUT_3D_SIZE 2\n0 0 0\n"), "wrong entry count")
        XCTAssertThrowsError(try CubeLUT.parse("LUT_1D_SIZE 4\n0\n0.3\n0.6\n1\n"), "1D unsupported")
    }

    // MARK: Grading behavior

    func testExposureRaisesLuma() throws {
        let brighter = ColorAdjustments(exposureEV: 1)
        let gray = RGB(0.2, 0.2, 0.2)
        XCTAssertEqual(brighter.applied(to: gray).luma, 0.4, accuracy: 1e-9,
                       "+1 EV doubles linear light")
    }

    func testContrastPivotsAtMiddleGray() {
        let punchy = ColorAdjustments(contrast: 1.5)
        let pivot = RGB(0.18, 0.18, 0.18)
        XCTAssertEqual(punchy.applied(to: pivot).luma, 0.18, accuracy: 1e-9)
        XCTAssertLessThan(punchy.applied(to: RGB(0.05, 0.05, 0.05)).luma, 0.05)
        XCTAssertGreaterThan(punchy.applied(to: RGB(0.5, 0.5, 0.5)).luma, 0.5)
    }

    func testSaturationZeroIsGrayscale() {
        let mono = ColorAdjustments(saturation: 0).applied(to: RGB(0.8, 0.2, 0.4))
        XCTAssertEqual(mono.r, mono.g, accuracy: 1e-9)
        XCTAssertEqual(mono.g, mono.b, accuracy: 1e-9)
    }

    func testTemperatureWarmsAndCools() {
        let warm = ColorAdjustments(temperature: 0.5).applied(to: RGB(0.5, 0.5, 0.5))
        XCTAssertGreaterThan(warm.r, warm.b)
        let cool = ColorAdjustments(temperature: -0.5).applied(to: RGB(0.5, 0.5, 0.5))
        XCTAssertLessThan(cool.r, cool.b)
    }

    func testBakedLUTMatchesDirectApplication() throws {
        let grade = ColorAdjustments(exposureEV: 0.3, contrast: 1.2, saturation: 1.15,
                                     temperature: 0.1, tint: -0.05)
        let lut = try grade.lut(size: 33)
        for probe in [RGB(0.1, 0.4, 0.7), RGB(0.6, 0.6, 0.6), RGB(0.9, 0.2, 0.1)] {
            let direct = grade.applied(to: probe)
            let baked = lut.sample(probe)
            // Trilinear interpolation error stays small at size 33.
            XCTAssertEqual(baked.r, direct.r, accuracy: 0.01)
            XCTAssertEqual(baked.g, direct.g, accuracy: 0.01)
            XCTAssertEqual(baked.b, direct.b, accuracy: 0.01)
        }
    }

    // MARK: Auto white balance (gray-world)

    func testNeutralSceneNeedsNoCorrection() {
        let adjustments = AutoWhiteBalance.estimate(averageColor: RGB(0.4, 0.4, 0.4))
        XCTAssertEqual(adjustments.temperature, 0, accuracy: 1e-9)
        XCTAssertEqual(adjustments.tint, 0, accuracy: 1e-9)
    }

    func testWarmCastGetsCooled() {
        // Tungsten-ish scene: too much red, too little blue.
        let warm = RGB(0.55, 0.45, 0.35)
        let fix = AutoWhiteBalance.estimate(averageColor: warm)
        XCTAssertLessThan(fix.temperature, 0, "warm cast needs a cooling correction")
        let corrected = fix.applied(to: warm)
        XCTAssertEqual(corrected.r, corrected.b, accuracy: 0.03,
                       "red/blue must roughly meet after correction")
    }

    func testGreenCastGetsTintCorrection() {
        let fluorescent = RGB(0.42, 0.5, 0.42)
        let fix = AutoWhiteBalance.estimate(averageColor: fluorescent)
        XCTAssertGreaterThan(fix.tint, 0, "green cast pushes tint toward magenta")
        let corrected = fix.applied(to: fluorescent)
        XCTAssertEqual(corrected.g, (corrected.r + corrected.b) / 2, accuracy: 0.02)
    }

    func testDegenerateScenesReturnIdentity() {
        XCTAssertTrue(AutoWhiteBalance.estimate(averageColor: RGB(0.001, 0.001, 0.001)).isIdentity,
                      "black frame carries no evidence")
        XCTAssertTrue(AutoWhiteBalance.estimate(averageColor: RGB(1, 1, 1)).isIdentity,
                      "blown frame carries no evidence")
        XCTAssertTrue(AutoWhiteBalance.estimate(frameAverages: []).isIdentity)
    }

    func testFrameAveragingMatchesSingleEstimate() {
        let frames = [RGB(0.5, 0.45, 0.4), RGB(0.6, 0.45, 0.3), RGB(0.55, 0.45, 0.35)]
        let combined = AutoWhiteBalance.estimate(frameAverages: frames)
        let direct = AutoWhiteBalance.estimate(averageColor: RGB(0.55, 0.45, 0.35))
        XCTAssertEqual(combined.temperature, direct.temperature, accuracy: 1e-9)
        XCTAssertEqual(combined.tint, direct.tint, accuracy: 1e-9)
    }

    func testIdentityAdjustmentsAreIdentity() throws {
        XCTAssertTrue(ColorAdjustments().isIdentity)
        let lut = try ColorAdjustments().lut(size: 9)
        let probe = RGB(0.3, 0.6, 0.9)
        let out = lut.sample(probe)
        XCTAssertEqual(out.r, probe.r, accuracy: 1e-9)
        XCTAssertEqual(out.b, probe.b, accuracy: 1e-9)
    }
}
