import XCTest
import GhostlyCore
import GhostlyDomain
@testable import GhostlyFCPXML

/// FCP multicam emission (ซิงก์มุมกล้อง): a `media/multicam` resource with
/// sync-delayed angles plus one `mc-clip` spanning the whole span.
final class MulticamTests: XCTestCase {
    private func angle(_ name: String, path: String, seconds: Double,
                       delay: Double) -> FCPXMLWriter.MulticamAngle {
        let asset = Asset(name: name, url: URL(fileURLWithPath: path),
                          duration: RationalTime(seconds: seconds, preferredTimescale: 48_000),
                          kind: .video, format: .hd1080p30)
        return FCPXMLWriter.MulticamAngle(
            asset: asset,
            delay: RationalTime(seconds: delay, preferredTimescale: 48_000))
    }

    func testMulticamDocumentStructureAndValidation() throws {
        let document = try FCPXMLWriter().multicamDocument(
            name: "มัลติแคม",
            angles: [angle("กล้อง A.mov", path: "/footage/กล้อง A.mov", seconds: 60, delay: 2),
                     angle("กล้อง B.mov", path: "/footage/กล้อง B.mov", seconds: 58, delay: 0)],
            format: .hd1080p30)

        XCTAssertTrue(document.contains("<multicam "))
        XCTAssertEqual(document.components(separatedBy: "<mc-angle ").count - 1, 2)
        XCTAssertTrue(document.contains("angleID=\"A1\""))
        XCTAssertTrue(document.contains("angleID=\"A2\""))
        XCTAssertTrue(document.contains("<mc-clip "))
        XCTAssertTrue(document.contains("มัลติแคม"))
        // Real file URLs, percent-encoded, must survive into the assets.
        XCTAssertTrue(document.contains("src=\"file:///footage/"))

        let issues = FCPXMLValidator().validate(document)
        XCTAssertFalse(issues.contains { $0.severity == .error },
                       "issues: \(issues.map(\.description))")
    }

    func testTotalSpanCoversLatestAngle() throws {
        // Angle B: delay 3 s + 10 s duration → the mc-clip must span 13 s.
        let document = try FCPXMLWriter().multicamDocument(
            name: "MC",
            angles: [angle("A", path: "/a.mov", seconds: 8, delay: 0),
                     angle("B", path: "/b.mov", seconds: 10, delay: 3)],
            format: .hd1080p30)
        let snapped = VideoFormat.hd1080p30.frameRate
            .snapped(RationalTime(seconds: 13, preferredTimescale: 48_000))
        XCTAssertTrue(document.contains("duration=\"\(snapped.description)\""),
                      "mc-clip duration must cover delay+duration of the last angle")
    }

    func testRejectsEmptyAngleList() {
        XCTAssertThrowsError(try FCPXMLWriter().multicamDocument(
            name: "MC", angles: [], format: .hd1080p30))
    }
}
