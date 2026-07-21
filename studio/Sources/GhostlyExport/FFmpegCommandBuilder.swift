import Foundation
import GhostlyCore
import GhostlyDomain

/// Builds deterministic FFmpeg argument vectors from a `RenderPreset`. Pure
/// and testable — it produces the argument array; a `Renderer` executes it.
/// The studio uses this both to drive real exports and to show users the
/// exact command that will run.
public struct FFmpegCommandBuilder: Sendable {
    public var executable: String

    public init(executable: String = "ffmpeg") {
        self.executable = executable
    }

    /// A cut to lift out of the source, in seconds (accurate, output-side
    /// seeking — the segment is re-encoded by the preset anyway).
    public struct Trim: Sendable, Equatable {
        public let startSeconds: Double
        public let endSeconds: Double

        public init(startSeconds: Double, endSeconds: Double) {
            self.startSeconds = startSeconds
            self.endSeconds = endSeconds
        }
    }

    /// The argument vector (excluding the executable) for a single export.
    /// - Parameters:
    ///   - input/output: source and destination paths.
    ///   - preset: the render recipe.
    ///   - metadata: optional tags to embed.
    ///   - trim: optional segment to cut (for highlight → short exports).
    ///   - overwrite: pass `-y` to overwrite an existing output.
    public func arguments(input: String, output: String, preset: RenderPreset,
                          metadata: ExportMetadata = ExportMetadata(),
                          trim: Trim? = nil,
                          overwrite: Bool = true) -> [String] {
        var args: [String] = []
        if overwrite { args.append("-y") }
        args += ["-i", input]
        if let trim {
            args += ["-ss", seconds(trim.startSeconds), "-to", seconds(trim.endSeconds)]
        }

        // Video codec + rate control.
        args += ["-c:v", videoCodecName(preset.videoCodec)]
        if let quality = preset.quality, preset.videoCodec != .proRes422 {
            args += ["-crf", String(quality)]
        } else if preset.videoCodec == .proRes422 {
            args += ["-profile:v", "2"] // ProRes 422 standard
        } else {
            args += ["-b:v", "\(preset.videoBitrateKbps)k",
                     "-maxrate", "\(preset.videoBitrateKbps)k",
                     "-bufsize", "\(preset.videoBitrateKbps * 2)k"]
        }

        // Frame rate + scale (force target format).
        args += ["-r", frameRateArg(preset.format.frameRate)]
        args += ["-vf", "scale=\(preset.format.width):\(preset.format.height)"]

        // Pixel format for broad player compatibility (8-bit 4:2:0).
        if preset.videoCodec == .h264 || preset.videoCodec == .hevc {
            args += ["-pix_fmt", "yuv420p"]
        }

        // Audio.
        args += ["-c:a", audioCodecName(preset.audioCodec)]
        if preset.audioCodec != .pcm {
            args += ["-b:a", "\(preset.audioBitrateKbps)k"]
        }

        // Faststart for progressive streaming of MP4/MOV.
        if preset.container == .mp4 || preset.container == .mov {
            args += ["-movflags", "+faststart"]
        }

        args += metadataArguments(metadata)
        args.append(output)
        return args
    }

    /// The full shell-display command (executable + args), shell-quoted.
    public func commandLine(input: String, output: String, preset: RenderPreset,
                            metadata: ExportMetadata = ExportMetadata(),
                            trim: Trim? = nil) -> String {
        let args = arguments(input: input, output: output, preset: preset,
                             metadata: metadata, trim: trim)
        return ([executable] + args).map(Self.shellQuote).joined(separator: " ")
    }

    // MARK: Helpers

    /// "12.5" / "8" — canonical seconds for -ss/-to.
    private func seconds(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(format: "%.3f", value)
    }

    private func metadataArguments(_ metadata: ExportMetadata) -> [String] {
        var args: [String] = []
        if let title = metadata.title { args += ["-metadata", "title=\(title)"] }
        if let artist = metadata.artist { args += ["-metadata", "artist=\(artist)"] }
        if let comment = metadata.comment { args += ["-metadata", "comment=\(comment)"] }
        if let year = metadata.year { args += ["-metadata", "date=\(year)"] }
        return args
    }

    private func videoCodecName(_ codec: RenderPreset.VideoCodec) -> String {
        switch codec {
        case .h264: return "libx264"
        case .hevc: return "libx265"
        case .vp9: return "libvpx-vp9"
        case .proRes422: return "prores_ks"
        }
    }

    private func audioCodecName(_ codec: RenderPreset.AudioCodec) -> String {
        switch codec {
        case .aac: return "aac"
        case .opus: return "libopus"
        case .pcm: return "pcm_s16le"
        }
    }

    /// FFmpeg accepts fractional rates as `num/den` — keeps NTSC rates exact.
    private func frameRateArg(_ rate: FrameRate) -> String {
        rate.secondsPerBatch == 1 ? String(rate.frames) : "\(rate.frames)/\(rate.secondsPerBatch)"
    }

    static func shellQuote(_ arg: String) -> String {
        guard arg.contains(where: { " \t\n\"'\\$`*?()[]{}|&;<>".contains($0) }) else { return arg }
        return "'" + arg.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
