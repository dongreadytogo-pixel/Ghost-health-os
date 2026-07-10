import XCTest
import GhostlyCore
import GhostlyDomain
import GhostlyDetection
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
        // The TikTok style wraps at 18 chars/line, so the 3 source cues split
        // into more captions — but never fewer, and no Thai text may be lost.
        XCTAssertGreaterThanOrEqual(output.captionCount, 3)
        XCTAssertGreaterThan(output.storylineClipCount, 0)
        XCTAssertTrue(output.fcpxml.contains("captionFormat=ITT.th"),
                      "captions must carry the Thai ITT role")
        // "สวัสดี" opens cue 1, so it survives any wrap point intact; longer
        // phrases may be split mid-word by the 18-char grapheme wrap.
        XCTAssertTrue(output.fcpxml.contains("สวัสดี"))
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

    // MARK: Real-audio path (WAV → detectors → edit)

    /// 12s "recording": narration-shaped tone bursts matching the Thai SRT.
    private func recordedClip() -> WAV.Audio {
        AudioFixture(sampleRate: 16_000)
            .silence(1.0).speech(2.5)
            .silence(0.5).speech(3.0)
            .silence(1.0).speech(3.0)
            .silence(1.0)
            .audio()
    }

    func testAudioOnlyEditNeedsNoTranscript() throws {
        let output = try EditPipeline.run(EditPipeline.AudioInput(
            audio: recordedClip(),
            command: "create a tiktok, remove silence"))
        XCTAssertTrue(output.isValid, "issues: \(output.issues)")
        XCTAssertGreaterThan(output.storylineClipCount, 0)
        XCTAssertEqual(output.captionCount, 0, "no transcript, no captions")
        XCTAssertTrue(output.isVertical)
    }

    func testAudioPlusThaiSRTAttachesCaptions() throws {
        let output = try EditPipeline.run(EditPipeline.AudioInput(
            audio: recordedClip(),
            subtitles: thaiSRT,
            command: "create a tiktok with captions, remove silence"))
        XCTAssertTrue(output.isValid, "issues: \(output.issues)")
        XCTAssertEqual(output.language, "th")
        XCTAssertGreaterThanOrEqual(output.captionCount, 3)
        XCTAssertTrue(output.fcpxml.contains("captionFormat=ITT.th"))
    }

    func testAudioEditReportsDetectedTempo() throws {
        let music = AudioFixture(sampleRate: 16_000)
            .speech(1.0)
            .beats(bpm: 120, seconds: 5)
            .audio()
        let output = try EditPipeline.run(EditPipeline.AudioInput(
            audio: music, command: "edit this like a vlog"))
        let bpm = try XCTUnwrap(output.detectedBPM)
        XCTAssertEqual(bpm, 120, accuracy: 8)
    }

    func testDiarizationTagsCaptionSpeakers() throws {
        // Interview: low voice asks (1–2.5s), high voice answers (3.5–5.5s).
        let interview = AudioFixture(sampleRate: 16_000)
            .silence(1.0).tone(frequency: 150, seconds: 1.5)
            .silence(1.0).tone(frequency: 310, seconds: 2.0)
            .silence(0.5)
            .audio()
        let srt = """
        1
        00:00:01,000 --> 00:00:02,500
        วันนี้เป็นยังไงบ้างครับ

        2
        00:00:03,500 --> 00:00:05,500
        สบายดีค่ะ ขอบคุณมากนะคะ
        """
        let output = try EditPipeline.run(EditPipeline.AudioInput(
            audio: interview, subtitles: srt,
            command: "create a tiktok with captions",
            diarize: true))
        XCTAssertTrue(output.isValid, "issues: \(output.issues)")
        XCTAssertEqual(output.speakerCount, 2)

        // The tagged transcript flows through: verify via the same seam.
        let turns = SpeakerDiarizer().turns(
            samples: interview.samples, sampleRate: interview.sampleRate,
            speechRanges: SilenceDetector().speechRanges(
                samples: interview.samples, sampleRate: interview.sampleRate))
        let track = try SRT.parse(srt)
        let tagged = EditPipeline.attributingSpeakers(
            SubtitleTrack(language: "th", cues: track.cues), turns: turns)
        XCTAssertEqual(tagged.cues.map(\.speaker), ["S1", "S2"])
    }

    func testAudioEditRejectsSilenceAndEmpty() {
        XCTAssertThrowsError(try EditPipeline.run(EditPipeline.AudioInput(
            audio: WAV.Audio(samples: [], sampleRate: 16_000),
            command: "create a tiktok")))
        XCTAssertThrowsError(try EditPipeline.run(EditPipeline.AudioInput(
            audio: AudioFixture(sampleRate: 16_000).silence(5).audio(),
            command: "create a tiktok")), "pure silence has nothing to edit")
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
