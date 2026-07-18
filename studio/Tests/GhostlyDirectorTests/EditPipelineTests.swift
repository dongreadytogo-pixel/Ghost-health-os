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

    // MARK: Custom Title subtitle layer (ซับแบบ Title)

    func testTitleSubtitleLayerIsSeparateAndAdditional() throws {
        let output = try EditPipeline.run(EditPipeline.Input(
            subtitles: thaiSRT, durationSeconds: 12,
            command: "ทำเป็นติ๊กต๊อก ใส่ซับแบบ Title"))
        XCTAssertTrue(output.isValid, "issues: \(output.issues)")
        XCTAssertGreaterThanOrEqual(output.titleSubtitleCount, 3)
        // Both layers exist: the standard Thai caption track AND the
        // stylable Title overlays on their own lane.
        XCTAssertTrue(output.fcpxml.contains("captionFormat=ITT.th"),
                      "caption track must remain")
        XCTAssertTrue(output.fcpxml.contains("<title "),
                      "Title overlays must be emitted")
        XCTAssertTrue(output.fcpxml.contains("lane=\"2\""),
                      "Title subs live on their own lane")
        XCTAssertTrue(output.fcpxml.contains("Basic Title"))
    }

    func testNoTitleLayerWithoutTheOption() throws {
        let output = try EditPipeline.run(EditPipeline.Input(
            subtitles: thaiSRT, durationSeconds: 12,
            command: "ทำเป็นติ๊กต๊อก ใส่ซับ"))
        XCTAssertEqual(output.titleSubtitleCount, 0)
        XCTAssertFalse(output.fcpxml.contains("<title "),
                       "no Title overlays unless asked")
    }

    // MARK: Smart Thai command — length cap + highlight emphasis

    func testThaiDurationCapKeepsBestWithinBudget() throws {
        // 8.5 s of speech must shrink to the best ≤5 s selection.
        let output = try EditPipeline.run(EditPipeline.Input(
            subtitles: thaiSRT, durationSeconds: 12,
            command: "คัตเสียงคลิปนี้โดยเน้นประโยคสำคัญที่น่าสนใจ ความยาวเหลือไม่เกิน 5 วินาที"))
        XCTAssertTrue(output.isValid, "issues: \(output.issues)")
        XCTAssertGreaterThan(output.storylineClipCount, 0)
        XCTAssertGreaterThan(output.durationSeconds, 0)
        XCTAssertLessThanOrEqual(output.durationSeconds, 5.01,
                                 "ความยาวต้องไม่เกินงบ 5 วินาที")
    }

    func testDurationCapLooseEnoughIsANoOp() throws {
        let capped = try EditPipeline.run(EditPipeline.Input(
            subtitles: thaiSRT, durationSeconds: 12,
            command: "ตัดช่วงเงียบออก ไม่เกิน 10 นาที"))
        let plain = try EditPipeline.run(EditPipeline.Input(
            subtitles: thaiSRT, durationSeconds: 12,
            command: "ตัดช่วงเงียบออก"))
        XCTAssertEqual(capped.durationSeconds, plain.durationSeconds, accuracy: 0.01,
                       "a cap above the edit length must change nothing")
    }

    // MARK: Real media reference (FCP must open the footage online)

    func testRealMediaURLLandsInAssetSrc() throws {
        // Thai filename: absoluteString percent-encodes it, and that exact
        // form must be what FCP reads back from the asset's src.
        let media = URL(fileURLWithPath: "/Users/editor/Footage/คลิปรีวิว.mov")
        let output = try EditPipeline.run(EditPipeline.Input(
            subtitles: thaiSRT, durationSeconds: 12,
            command: "create a tiktok with captions",
            mediaURL: media))
        XCTAssertTrue(output.isValid, "issues: \(output.issues)")
        XCTAssertTrue(output.fcpxml.contains("src=\"\(media.absoluteString)\""),
                      "FCPXML must reference the real footage, not a placeholder")
        XCTAssertFalse(output.fcpxml.contains("file:///media/"),
                       "placeholder path must be gone when real media is given")
    }

    func testWithoutMediaURLKeepsRelinkablePlaceholder() throws {
        let output = try EditPipeline.run(EditPipeline.Input(
            subtitles: thaiSRT, durationSeconds: 12, command: "add captions"))
        XCTAssertTrue(output.fcpxml.contains("src=\"file:///media/"),
                      "no-media (CI/transcript-only) runs keep the placeholder")
    }

    func testAudioEditCarriesRealMediaURL() throws {
        let media = URL(fileURLWithPath: "/Volumes/SSD/สัมภาษณ์.mp4")
        let output = try EditPipeline.run(EditPipeline.AudioInput(
            audio: recordedClip(),
            command: "remove silence",
            mediaURL: media))
        XCTAssertTrue(output.isValid, "issues: \(output.issues)")
        XCTAssertTrue(output.fcpxml.contains("src=\"\(media.absoluteString)\""))
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

    func testThaiCleanupCommandUnmasksSilence() throws {
        // Constant 50 Hz hum makes everything read as "speech" — the Thai
        // cleanup intent must scrub it so the two real bursts separate.
        let sampleRate = 16_000
        let voice = AudioFixture(sampleRate: sampleRate)
            .silence(1.0).speech(2.5).silence(1.5).speech(2.5).silence(1.0)
            .samples()
        let hum = AudioFixture(sampleRate: sampleRate)
            .tone(frequency: 50, seconds: 8.5, amplitude: 0.05).samples()
        let noisy = WAV.Audio(samples: zip(voice, hum).map(+), sampleRate: sampleRate)

        let dirty = try EditPipeline.run(EditPipeline.AudioInput(
            audio: noisy, command: "create a tiktok, remove silence"))
        XCTAssertFalse(dirty.audioCleaned)
        XCTAssertGreaterThan(dirty.durationSeconds, 7.5,
                             "hum floor masks the pauses: nothing gets removed")

        let cleaned = try EditPipeline.run(EditPipeline.AudioInput(
            audio: noisy, command: "ทำเป็นติ๊กต๊อก ตัดช่วงเงียบออก ลดเสียงรบกวน"))
        XCTAssertTrue(cleaned.audioCleaned)
        XCTAssertLessThan(cleaned.durationSeconds, 6.5,
                          "cleanup unmasks the pauses so silence removal bites")
        XCTAssertTrue(cleaned.isValid, "issues: \(cleaned.issues)")
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
