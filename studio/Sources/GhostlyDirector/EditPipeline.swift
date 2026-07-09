import Foundation
import GhostlyCore
import GhostlyDomain
import GhostlyDetection
import GhostlySubtitles
import GhostlyFCPXML

/// The end-to-end "edit for me" pipeline: a transcript (SRT/WebVTT) plus a
/// declared clip duration in, a validated FCPXML project out. This is the
/// engine behind `ghostly edit` and the `auto_edit` workflow: transcript cue
/// timings stand in for speech detection, so the full chain — intent →
/// pacing profile → auto-edit → captions → FCPXML — runs deterministically
/// with no media file, which is also what makes it CI-testable.
///
/// When real media is available, callers can transcribe first
/// (`GhostlyTranscription`) and feed the resulting track through the same
/// pipeline.
public enum EditPipeline {
    public struct Input: Sendable {
        /// SRT or WebVTT transcript content (WebVTT detected by header).
        public var subtitles: String
        /// Declared duration of the source clip, in seconds.
        public var durationSeconds: Double
        /// Natural-language editing command, e.g. "ตัดต่อแนว TikTok ใส่ซับ".
        public var command: String
        /// BCP-47 transcript language. Thai is the studio's primary language.
        public var language: String
        public var clipName: String
        public var projectName: String

        public init(subtitles: String,
                    durationSeconds: Double,
                    command: String,
                    language: String = "th",
                    clipName: String = "clip",
                    projectName: String = "AI Edit") {
            self.subtitles = subtitles
            self.durationSeconds = durationSeconds
            self.command = command
            self.language = language
            self.clipName = clipName
            self.projectName = projectName
        }
    }

    public struct Output: Sendable {
        public let fcpxml: String
        public let isValid: Bool
        /// Human-readable validation problems, if any.
        public let issues: [String]
        public let captionCount: Int
        public let storylineClipCount: Int
        public let durationSeconds: Double
        public let isVertical: Bool
        public let language: String
        public let profileStyle: String
    }

    public static func run(_ input: Input) throws -> Output {
        guard input.durationSeconds > 0 else {
            throw StudioError.invalidInput(field: "duration",
                                           reason: "clip duration must be positive seconds")
        }
        let duration = RationalTime(seconds: input.durationSeconds, preferredTimescale: 3000)

        // 1. Transcript → language-tagged subtitle track, clamped to the clip.
        let parsed = input.subtitles.hasPrefix("WEBVTT")
            ? try WebVTT.parse(input.subtitles)
            : try SRT.parse(input.subtitles)
        let cues = parsed.cues.compactMap { cue -> SubtitleCue? in
            guard cue.range.start < duration else { return nil }
            guard cue.range.end > duration else { return cue }
            return SubtitleCue(range: TimeRange(start: cue.range.start, end: duration),
                               text: cue.text, speaker: cue.speaker, words: cue.words)
        }
        guard !cues.isEmpty else {
            throw StudioError.invalidInput(
                field: "subtitles",
                reason: "no cues fall within the declared \(input.durationSeconds)s duration")
        }
        let transcript = SubtitleTrack(language: input.language, cues: cues)

        // 2. Intent → pacing profile.
        let plan = try Director().interpret(input.command)

        // 3. Cue timings double as speech ranges for the planner.
        let asset = Asset(
            name: input.clipName,
            url: URL(fileURLWithPath: "/media/\(input.clipName)"),
            duration: duration,
            kind: .video, format: plan.profile.format)
        let analysis = MediaAnalysis(
            assetID: asset.id,
            duration: duration,
            speechRanges: mergedRanges(cues.map(\.range)))

        // 4. Auto-edit + captions → validated FCPXML.
        let timeline = try AutoEditPlanner(profile: plan.profile).plan(
            footage: [(asset, analysis)],
            transcript: transcript,
            projectName: input.projectName)
        let project = Project(name: input.projectName, timeline: timeline)
        let document = try FCPXMLWriter().document(for: project, assets: [asset])
        let issues = FCPXMLValidator().validate(document)

        return Output(
            fcpxml: document,
            isValid: !issues.contains { $0.severity == .error },
            issues: issues.map(\.description),
            captionCount: timeline.captions.count,
            storylineClipCount: timeline.storyline.count,
            durationSeconds: timeline.duration.seconds,
            isVertical: timeline.format.isVertical,
            language: transcript.language,
            profileStyle: plan.profile.style.rawValue)
    }

    /// Merges overlapping/touching ranges so back-to-back cues form one
    /// continuous speech range instead of zero-length keeps.
    static func mergedRanges(_ ranges: [TimeRange]) -> [TimeRange] {
        let sorted = ranges.sorted { $0.start < $1.start }
        var out: [TimeRange] = []
        for range in sorted {
            if let last = out.last, range.start <= last.end {
                out[out.count - 1] = TimeRange(start: last.start, end: max(last.end, range.end))
            } else {
                out.append(range)
            }
        }
        return out
    }
}
