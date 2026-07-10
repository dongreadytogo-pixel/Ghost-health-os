import Foundation
import GhostlyCore
import GhostlyDetection
import GhostlyExport

/// Agent mode: one call that runs the whole delivery chain —
/// analyze (audio or transcript timings) → auto-edit → captions → FCPXML →
/// render-preset selection → the exact ffmpeg export command. Pure
/// orchestration over `EditPipeline` and `GhostlyExport`; every step is
/// reported in the result's trace so agents (and users) see what happened.
public enum Workflow {
    public struct Request: Sendable {
        /// Real audio; when nil, `subtitles` + `durationSeconds` drive the edit.
        public var audio: WAV.Audio?
        /// SRT/WebVTT transcript. Required when `audio` is nil.
        public var subtitles: String?
        /// Declared clip length; required when `audio` is nil.
        public var durationSeconds: Double?
        public var command: String
        public var language: String
        public var diarize: Bool
        public var clipName: String
        public var projectName: String
        /// Explicit render preset; nil infers one from the edit's format.
        public var exportPresetName: String?

        public init(audio: WAV.Audio? = nil,
                    subtitles: String? = nil,
                    durationSeconds: Double? = nil,
                    command: String,
                    language: String = "th",
                    diarize: Bool = false,
                    clipName: String = "clip",
                    projectName: String = "AI Edit",
                    exportPresetName: String? = nil) {
            self.audio = audio
            self.subtitles = subtitles
            self.durationSeconds = durationSeconds
            self.command = command
            self.language = language
            self.diarize = diarize
            self.clipName = clipName
            self.projectName = projectName
            self.exportPresetName = exportPresetName
        }
    }

    public struct Result: Sendable {
        public let edit: EditPipeline.Output
        public let exportPresetName: String
        /// Ready-to-run ffmpeg command rendering the (externally exported)
        /// master into the chosen delivery format.
        public let exportCommand: String
        /// Human-readable trace of every step, in execution order.
        public let steps: [String]
    }

    public static func run(_ request: Request) throws -> Result {
        var steps: [String] = []

        // 1–4. Analyze → plan → captions → FCPXML via the edit pipeline.
        let edit: EditPipeline.Output
        if let audio = request.audio {
            edit = try EditPipeline.run(EditPipeline.AudioInput(
                audio: audio,
                subtitles: request.subtitles,
                command: request.command,
                language: request.language,
                clipName: request.clipName,
                projectName: request.projectName,
                diarize: request.diarize))
            steps.append(String(format: "analyzed %.1fs of audio", audio.duration.seconds))
            if let bpm = edit.detectedBPM {
                steps.append(String(format: "detected tempo ≈ %.0f BPM", bpm))
            }
            if let speakers = edit.speakerCount {
                steps.append("diarized \(speakers) speaker(s)")
            }
        } else {
            guard let subtitles = request.subtitles, let seconds = request.durationSeconds else {
                throw StudioError.invalidInput(
                    field: "audio",
                    reason: "provide audio, or subtitles with durationSeconds")
            }
            edit = try EditPipeline.run(EditPipeline.Input(
                subtitles: subtitles,
                durationSeconds: seconds,
                command: request.command,
                language: request.language,
                clipName: request.clipName,
                projectName: request.projectName))
            steps.append(String(format: "used transcript timings over a declared %.1fs clip", seconds))
        }
        steps.append("planned \(edit.storylineClipCount) clip(s) with the '\(edit.profileStyle)' profile")
        if edit.captionCount > 0 {
            steps.append("attached \(edit.captionCount) '\(edit.language)' caption(s)")
        }
        let shape = edit.isVertical ? "9:16 vertical" : "landscape"
        steps.append("emitted valid FCPXML (\(String(format: "%.2f", edit.durationSeconds))s, \(shape))")

        // 5. Render preset: explicit or inferred from the edit's format.
        let preset: RenderPreset
        if let name = request.exportPresetName {
            guard let found = RenderPreset.named(name) else {
                throw StudioError.notFound(entity: "render preset", id: name)
            }
            preset = found
        } else {
            preset = RenderPreset.named(edit.isVertical ? "TikTok" : "YouTube 1080p")
                ?? RenderPreset.builtIn[0]
        }
        steps.append("selected render preset '\(preset.name)'")

        // 6. The exact export command for the rendered master.
        let base = (request.clipName as NSString).deletingPathExtension
        let output = "\(base)-\(preset.name.replacingOccurrences(of: " ", with: "")).\(preset.container.rawValue)"
        let exportCommand = FFmpegCommandBuilder().commandLine(
            input: request.clipName, output: output, preset: preset,
            metadata: ExportMetadata(title: request.projectName))
        steps.append("built ffmpeg export command → \(output)")

        return Result(edit: edit,
                      exportPresetName: preset.name,
                      exportCommand: exportCommand,
                      steps: steps)
    }
}
