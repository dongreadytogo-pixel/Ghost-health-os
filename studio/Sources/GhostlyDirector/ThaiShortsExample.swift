import Foundation
import GhostlyCore
import GhostlyDomain
import GhostlyDetection
import GhostlySubtitles
import GhostlyFCPXML

/// A self-contained, fixture-driven demonstration of the full pipeline for a
/// **Thai-language vertical short** — no real media required. It analyzes
/// fixture footage, plans a TikTok-style vertical edit, attaches Thai
/// captions, and emits validated FCPXML with a Thai caption role (`ITT.th`).
///
/// Used by the `ghostly demo-thai` CLI command and covered by tests, so the
/// Thai path is exercised end-to-end on every CI run.
public enum ThaiShortsExample {
    public struct Result: Sendable {
        public let fcpxml: String
        public let isValid: Bool
        /// Human-readable validation problems, if any.
        public let issues: [String]
        public let captionCount: Int
        public let durationSeconds: Double
        public let isVertical: Bool
        /// The planned timeline itself (drives the GUI inspector demo).
        public let timeline: Timeline
    }

    /// A short Thai transcript (SRT) with timings, as an ASR step would yield.
    public static let thaiTranscriptSRT = """
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

    /// Builds the demo and returns the emitted FCPXML plus a summary.
    public static func build(projectName: String = "รีวิวกล้อง (Thai Short)") throws -> Result {
        // 1. Fixture footage: one 12s vertical talking-head clip with speech.
        let asset = Asset(
            name: "talking-head",
            url: URL(string: "file:///media/talking-head.mov")!,
            duration: RationalTime(seconds: 12, preferredTimescale: 3000),
            kind: .video, format: .vertical1080x1920p30)
        let analysis = MediaAnalysis(
            assetID: asset.id,
            duration: asset.duration,
            speechRanges: [
                TimeRange(start: RationalTime(seconds: 1), end: RationalTime(seconds: 3.5)),
                TimeRange(start: RationalTime(seconds: 4), end: RationalTime(seconds: 7)),
                TimeRange(start: RationalTime(seconds: 8), end: RationalTime(seconds: 11)),
            ])

        // 2. Thai transcript → a Thai-language subtitle track.
        let parsed = try SRT.parse(thaiTranscriptSRT)
        let transcript = SubtitleTrack(language: "th", cues: parsed.cues)

        // 3. Plan a vertical TikTok-style edit and attach the Thai captions.
        let plan = try Director().interpret("create a tiktok with captions, remove silence")
        let timeline = try AutoEditPlanner(profile: plan.profile).plan(
            footage: [(asset, analysis)],
            transcript: transcript,
            projectName: projectName)

        // 4. Emit and validate FCPXML.
        let project = Project(name: projectName, timeline: timeline)
        let document = try FCPXMLWriter().document(for: project, assets: [asset])
        let issues = FCPXMLValidator().validate(document)
        let errors = issues.filter { $0.severity == .error }

        return Result(
            fcpxml: document,
            isValid: errors.isEmpty,
            issues: issues.map(\.description),
            captionCount: timeline.captions.count,
            durationSeconds: timeline.duration.seconds,
            isVertical: timeline.format.isVertical,
            timeline: timeline)
    }
}
