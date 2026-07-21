import XCTest
@testable import GhostlyDirector

/// End-to-end coverage of the Thai vertical-short demo: the whole pipeline
/// (analyze → plan → caption → FCPXML) must run and produce valid,
/// Thai-tagged FCPXML with no real media.
final class ThaiShortsExampleTests: XCTestCase {
    func testBuildsValidThaiVerticalShort() throws {
        let result = try ThaiShortsExample.build()

        XCTAssertTrue(result.isValid, "emitted FCPXML must pass validation: \(result.issues)")
        XCTAssertTrue(result.isVertical, "TikTok short must be vertical (9:16)")
        XCTAssertGreaterThan(result.captionCount, 0, "Thai captions must be attached")
        XCTAssertGreaterThan(result.durationSeconds, 0)
    }

    func testFCPXMLCarriesThaiCaptionRoleAndText() throws {
        let doc = try ThaiShortsExample.build().fcpxml
        XCTAssertTrue(doc.contains("<fcpxml"))
        XCTAssertTrue(doc.contains("captionFormat=ITT.th"), "captions must use the Thai role")
        XCTAssertTrue(doc.contains("สวัสดีครับ"), "Thai caption text must survive into the FCPXML")
        // Vertical format dimensions present.
        XCTAssertTrue(doc.contains("width=\"1080\""))
        XCTAssertTrue(doc.contains("height=\"1920\""))
    }

    func testDeterministic() throws {
        let a = try ThaiShortsExample.build().fcpxml
        let b = try ThaiShortsExample.build().fcpxml
        XCTAssertEqual(a, b, "the demo must be reproducible")
    }
}
