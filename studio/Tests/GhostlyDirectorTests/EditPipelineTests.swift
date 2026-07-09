import XCTest
import GhostlyCore
import GhostlyDomain
import GhostlySubtitles
@testable import GhostlyDirector

final class EditPipelineTests: XCTestCase {
    /// Thai review transcript, as ASR (or a human) would deliver it.
    private let thaiSRT = """
    1
    00:00:01,000 --> 00:00:03,500
    สวัสดีครับวันนี้เราจะมารีวิวกล้องตัวใหม่

    2
    00:00:04,000 --> 00:00:07,000
    กล้องตัวนี้ถ่ายวิดีโอได้สวยมากในที่แสงน้อย

    3
    00:00:08,000 --> 00:00:11,000
    ใครสนใจอย่าลืมกดติดตามช่องของเราด้วยนะครับ
    """

    // MARK: End-to-end (Thai-first)

    func testThaiSRTToValidVerticalFCPXML() throws {
        let output = try EditPipeline.run(EditPipeline.Input(
            subtitles: thaiSRT, durationSeconds: 12,
            command: "create a tiktok with captions, remove silence",
            clipName: "รีวิวกล้อง.mov", projectName: "Thai Short"))
        XCTAssertTrue(output.isValid, "issues: \(output.issues)")
        XCTAssertTrue(output.isVertical, "tiktok command must yield a 9:16 edit")
        XCTAssertEqual(output.language, "th")
        XCTAssertEqual(output.captionCount, 3)
        XCTAssertGreaterThan(output.storylineClipCount, 0)
        XCTAssertTrue(output.fcpxml.contains("captionFormat=ITT.th"),
                      "captions must carry the Thai ITT role")
        XCTAssertTrue(output.fcpxml.contains("สวัสดีครับ"))
    }

    func testDefaultsToThai() throws {
        let input = EditPipeline.Input(subtitles: thaiSRT, durationSeconds: 12,
                                       command: "add captions")
        XCTAssertEqual(input.language, "th", "Thai is the studio's primary language")
        let output = try EditPipeline.run(input)
        XCTAssertEqual(output.language, "th")
    }

    func testDeterministicOutput() throws {
        let input = EditPipeline.Input(subtitles: thaiSRT, durationSeconds: 12,
                                       command: "create a tiktok with captions")
        let a = try EditPipeline.run(input)
        let b = try EditPipeline.run(input)
        XCTAssertEqual(a.fcpxml, b.fcpxml, "same inputs must give byte-identical FCPXML")
    }

    func testWebVTTInputAccepted() throws {
        let vtt = """
        WEBVTT

        00:00:01.000 --> 00:00:03.000
        สวัสดีครับ

        00:00:04.000 --> 00:00:06.000
        วันนี้อากาศดีมาก
        """
        let output = try EditPipeline.run(EditPipeline.Input(
            subtitles: vtt, durationSeconds: 8, command: "add captions"))
        XCTAssertTrue(output.isValid, "issues: \(output.issues)")
        XCTAssertEqual(output.captionCount, 2)
    }

    // MARK: Clamping & failure modes

    func testCuesBeyondDurationAreClampedOrDropped() throws {
        // Cue 3 ends at 11s but the clip is declared 9.5s long: the cue that
        // starts inside is clamped; nothing may reference time past the media.
        let output = try EditPipeline.run(EditPipeline.Input(
            subtitles: thaiSRT, durationSeconds: 9.5, command: "add captions"))
        XCTAssertTrue(output.isValid, "issues: \(output.issues)")
        // Caption 3 may be dropped if silence removal compacts the timeline
        // below its 8s start; the first two must always survive.
        XCTAssertGreaterThanOrEqual(output.captionCount, 2)
        XCTAssertLessThanOrEqual(output.durationSeconds, 9.5 + 0.001)

        // Declared duration before every cue → nothing to edit.
        XCTAssertThrowsError(try EditPipeline.run(EditPipeline.Input(
            subtitles: thaiSRT, durationSeconds: 0.5, command: "add captions")))
    }

    func testRejectsNonPositiveDurationAndBadSubtitles() {
        XCTAssertThrowsError(try EditPipeline.run(EditPipeline.Input(
            subtitles: thaiSRT, durationSeconds: 0, command: "add captions")))
        XCTAssertThrowsError(try EditPipeline.run(EditPipeline.Input(
            subtitles: "not a subtitle file", durationSeconds: 10, command: "add captions")))
    }

    // MARK: Range merging

    func testMergedRangesJoinsTouchingAndOverlapping() {
        let ranges = [
            TimeRange(start: RationalTime(seconds: 4), end: RationalTime(seconds: 6)),
            TimeRange(start: RationalTime(seconds: 1), end: RationalTime(seconds: 3)),
            TimeRange(start: RationalTime(seconds: 3), end: RationalTime(seconds: 4)),
            TimeRange(start: RationalTime(seconds: 8), end: RationalTime(seconds: 9)),
        ]
        let merged = EditPipeline.mergedRanges(ranges)
        XCTAssertEqual(merged.count, 2)
        XCTAssertEqual(merged[0].start.seconds, 1)
        XCTAssertEqual(merged[0].end.seconds, 6)
        XCTAssertEqual(merged[1].start.seconds, 8)
    }
}
