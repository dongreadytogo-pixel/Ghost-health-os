import XCTest
import GhostlyCore
import GhostlyDomain
import GhostlyDetection
import GhostlySubtitles
@testable import GhostlyDirector

/// YouTube chapter export: the timestamps a Thai creator pastes into a
/// video description, and YouTube's own validity rules.
final class ChapterExportTests: XCTestCase {
    private func chapter(_ seconds: Double, _ title: String) -> Marker {
        Marker(start: RationalTime(seconds: seconds), text: title, kind: .chapter)
    }

    func testFormatsYouTubeDescription() throws {
        let markers = [
            chapter(0, "บทนำ"),
            chapter(45, "รีวิวกล้อง"),
            chapter(130, "ทดสอบกลางคืน"),
        ]
        let text = try XCTUnwrap(ChapterExport.youTubeDescription(
            markers: markers, duration: RationalTime(seconds: 200)))
        XCTAssertEqual(text, "0:00 บทนำ\n0:45 รีวิวกล้อง\n2:10 ทดสอบกลางคืน")
    }

    func testHourFormatting() {
        XCTAssertEqual(ChapterExport.timestamp(0), "0:00")
        XCTAssertEqual(ChapterExport.timestamp(65), "1:05")
        XCTAssertEqual(ChapterExport.timestamp(3661), "1:01:01")
        XCTAssertEqual(ChapterExport.timestamp(3600), "1:00:00")
    }

    func testRequiresFirstChapterAtZero() {
        // YouTube ignores chapter lists that don't start at 0:00.
        let markers = [chapter(5, "A"), chapter(40, "B"), chapter(90, "C")]
        XCTAssertNil(ChapterExport.youTubeDescription(
            markers: markers, duration: RationalTime(seconds: 150)))
    }

    func testRequiresAtLeastThreeChapters() {
        let markers = [chapter(0, "A"), chapter(60, "B")]
        XCTAssertNil(ChapterExport.youTubeDescription(
            markers: markers, duration: RationalTime(seconds: 150)))
    }

    func testRejectsTooShortChapters() {
        // Middle chapter is only 5 s (40→45); YouTube requires ≥10 s.
        let markers = [chapter(0, "A"), chapter(40, "B"), chapter(45, "C")]
        XCTAssertNil(ChapterExport.youTubeDescription(
            markers: markers, duration: RationalTime(seconds: 120)))
    }

    func testLastChapterMeasuredAgainstDuration() {
        // Last chapter at 110 s with a 115 s video is only 5 s → invalid.
        let markers = [chapter(0, "A"), chapter(50, "B"), chapter(110, "C")]
        XCTAssertNil(ChapterExport.youTubeDescription(
            markers: markers, duration: RationalTime(seconds: 115)))
    }

    func testIgnoresNonChapterMarkers() throws {
        var markers = [chapter(0, "บทนำ"), chapter(30, "ช่วงสอง"), chapter(60, "ช่วงสาม")]
        markers.append(Marker(start: RationalTime(seconds: 15), text: "note", kind: .standard))
        let text = try XCTUnwrap(ChapterExport.youTubeDescription(
            markers: markers, duration: RationalTime(seconds: 90)))
        XCTAssertFalse(text.contains("note"))
        XCTAssertEqual(text.components(separatedBy: "\n").count, 3)
    }

    func testEndToEndFromTranscript() throws {
        // A transcript over a 3-minute clip yields a valid chapter list.
        let cues = (0..<6).map { i in
            SubtitleCue(range: TimeRange(start: RationalTime(seconds: Double(i) * 30),
                                         end: RationalTime(seconds: Double(i) * 30 + 25)),
                        text: "ช่วงที่ \(i + 1)")
        }
        let transcript = SubtitleTrack(language: "th", cues: cues)
        let duration = RationalTime(seconds: 180)
        let asset = Asset(name: "v", url: URL(fileURLWithPath: "/v"),
                          duration: duration, kind: .video)
        let analysis = MediaAnalysis(assetID: asset.id, duration: duration,
                                     speechRanges: cues.map(\.range))
        let markers = HighlightPlanner().chapters(from: analysis, transcript: transcript)
        let text = try XCTUnwrap(ChapterExport.youTubeDescription(
            markers: markers, duration: duration))
        XCTAssertTrue(text.hasPrefix("0:00 "))
        XCTAssertGreaterThanOrEqual(text.components(separatedBy: "\n").count, 3)
    }
}
