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

    /// Real-audio variant: speech ranges come from the `SilenceDetector`
    /// (and tempo from the `BeatDetector`) instead of transcript timings, so
    /// an actually recorded clip — decoded via `WAV` — can be auto-edited
    /// with no transcript at all. Pass `subtitles` too when a transcript
    /// exists and captions should be attached.
    public struct AudioInput: Sendable {
        public var audio: WAV.Audio
        /// Optional SRT/WebVTT transcript for captions.
        public var subtitles: String?
        public var command: String
        public var language: String
        public var clipName: String
        public var projectName: String
        /// Attribute captions to speakers by voice similarity (S1, S2, …).
        public var diarize: Bool
        /// Clean the audio before detection; the command's "ลดเสียงรบกวน" /
        /// "clean audio" intent enables this automatically.
        public var cleanAudio: Bool

        public init(audio: WAV.Audio,
                    subtitles: String? = nil,
                    command: String,
                    language: String = "th",
                    clipName: String = "clip",
                    projectName: String = "AI Edit",
                    diarize: Bool = false,
                    cleanAudio: Bool = false) {
            self.audio = audio
            self.subtitles = subtitles
            self.command = command
            self.language = language
            self.clipName = clipName
            self.projectName = projectName
            self.diarize = diarize
            self.cleanAudio = cleanAudio
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
        /// Tempo detected from real audio; nil on the transcript-only path.
        public let detectedBPM: Double?
        /// Distinct voices found by diarization; nil when not requested.
        public let speakerCount: Int?
        /// Caption style the profile attached (e.g. "TikTok"); nil when the
        /// edit carries no captions.
        public let captionStyleName: String?
        /// True when audio cleanup ran before detection.
        public let audioCleaned: Bool
    }

    public static func run(_ input: Input) throws -> Output {
        guard input.durationSeconds > 0 else {
            throw StudioError.invalidInput(field: "duration",
                                           reason: "clip duration must be positive seconds")
        }
        let duration = RationalTime(seconds: input.durationSeconds, preferredTimescale: 3000)
        guard let transcript = try transcriptTrack(from: input.subtitles,
                                                   language: input.language,
                                                   clampedTo: duration) else {
            throw StudioError.invalidInput(
                field: "subtitles",
                reason: "no cues fall within the declared \(input.durationSeconds)s duration")
        }
        // Cue timings double as speech ranges for the planner.
        return try compose(command: input.command,
                           duration: duration,
                           speechRanges: mergedRanges(transcript.cues.map(\.range)),
                           beats: [], bpm: nil,
                           transcript: transcript,
                           clipName: input.clipName,
                           projectName: input.projectName,
                           speakerCount: nil,
                           audioCleaned: false)
    }

    public static func run(_ input: AudioInput) throws -> Output {
        let audio = input.audio
        guard !audio.samples.isEmpty, audio.sampleRate > 0 else {
            throw StudioError.invalidInput(field: "audio", reason: "no audio samples")
        }
        // Cleanup before detection when the command asks ("ลดเสียงรบกวน") —
        // hum/rumble otherwise reads as speech to the silence detector.
        // 50 Hz mains: Thai-first default.
        let wantsCleanup = input.cleanAudio
            || (try? Director().interpret(input.command))?.wantsAudioCleanup == true
        let samples = wantsCleanup
            ? AudioCleanup(humHz: 50).process(audio.samples, sampleRate: audio.sampleRate)
            : audio.samples
        let speech = SilenceDetector().speechRanges(samples: samples,
                                                    sampleRate: audio.sampleRate)
        guard !speech.isEmpty else {
            throw StudioError.validationFailure(
                detail: "no speech found in \(String(format: "%.1f", audio.duration.seconds))s of audio")
        }
        let beats = BeatDetector().detect(samples: samples, sampleRate: audio.sampleRate)
        var transcript = try input.subtitles.flatMap {
            try transcriptTrack(from: $0, language: input.language, clampedTo: audio.duration)
        }
        var speakerCount: Int?
        if input.diarize {
            let turns = SpeakerDiarizer().turns(samples: samples,
                                                sampleRate: audio.sampleRate,
                                                speechRanges: speech)
            speakerCount = SpeakerDiarizer.speakerCount(turns)
            if let track = transcript {
                transcript = attributingSpeakers(track, turns: turns)
            }
        }
        return try compose(command: input.command,
                           duration: audio.duration,
                           speechRanges: speech,
                           beats: beats.beats, bpm: beats.bpm,
                           transcript: transcript,
                           clipName: input.clipName,
                           projectName: input.projectName,
                           speakerCount: speakerCount,
                           audioCleaned: wantsCleanup)
    }

    /// Tags each cue with the speaker whose turn overlaps it the most.
    static func attributingSpeakers(_ track: SubtitleTrack,
                                    turns: [SpeakerTurn]) -> SubtitleTrack {
        guard !turns.isEmpty else { return track }
        var out = track
        out.cues = track.cues.map { cue in
            var best: (speaker: String, seconds: Double)?
            for turn in turns {
                guard let overlap = cue.range.intersection(turn.range) else { continue }
                let seconds = overlap.duration.seconds
                if seconds > (best?.seconds ?? 0) {
                    best = (turn.speaker, seconds)
                }
            }
            guard let best else { return cue }
            var tagged = cue
            tagged.speaker = best.speaker
            return tagged
        }
        return out
    }

    // MARK: Shared core

    /// Parses SRT/WebVTT and clamps cues to the clip; nil when no cue starts
    /// inside the clip.
    private static func transcriptTrack(from subtitles: String, language: String,
                                        clampedTo duration: RationalTime) throws -> SubtitleTrack? {
        let parsed = subtitles.hasPrefix("WEBVTT")
            ? try WebVTT.parse(subtitles)
            : try SRT.parse(subtitles)
        let cues = parsed.cues.compactMap { cue -> SubtitleCue? in
            guard cue.range.start < duration else { return nil }
            guard cue.range.end > duration else { return cue }
            return SubtitleCue(range: TimeRange(start: cue.range.start, end: duration),
                               text: cue.text, speaker: cue.speaker, words: cue.words)
        }
        guard !cues.isEmpty else { return nil }
        return SubtitleTrack(language: language, cues: cues)
    }

    private static func compose(command: String,
                                duration: RationalTime,
                                speechRanges: [TimeRange],
                                beats: [RationalTime], bpm: Double?,
                                transcript: SubtitleTrack?,
                                clipName: String,
                                projectName: String,
                                speakerCount: Int?,
                                audioCleaned: Bool) throws -> Output {
        let plan = try Director().interpret(command)
        let asset = Asset(
            name: clipName,
            url: URL(fileURLWithPath: "/media/\(clipName)"),
            duration: duration,
            kind: .video, format: plan.profile.format)
        let analysis = MediaAnalysis(
            assetID: asset.id,
            duration: duration,
            speechRanges: speechRanges,
            beats: beats, bpm: bpm)

        let timeline = try AutoEditPlanner(profile: plan.profile).plan(
            footage: [(asset, analysis)],
            transcript: transcript,
            projectName: projectName)
        let project = Project(name: projectName, timeline: timeline)
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
            language: transcript?.language ?? "und",
            profileStyle: plan.profile.style.rawValue,
            detectedBPM: bpm,
            speakerCount: speakerCount,
            captionStyleName: transcript == nil ? nil : plan.profile.captionStyleName,
            audioCleaned: audioCleaned)
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
