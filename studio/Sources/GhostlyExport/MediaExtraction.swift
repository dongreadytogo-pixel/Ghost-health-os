import Foundation
import GhostlyCore

/// Deterministic ffmpeg recipes for *pulling analysis inputs out of* media —
/// the inverse direction of `FFmpegCommandBuilder` (which renders deliverables).
/// The studio never assumes ffmpeg is installed: these produce the exact
/// argument vector / display command, and callers (CLI, GUI, agent tools)
/// either run it or show it to the user.
///
/// Typical chain on any platform:
///     extract-audio clip.mp4 → clip.wav → `ghostly edit --wav clip.wav`
public struct MediaExtraction: Sendable {
    public var executable: String

    public init(executable: String = "ffmpeg") {
        self.executable = executable
    }

    /// Mono 16-bit PCM WAV at an analysis-friendly rate — exactly what the
    /// `WAV` decoder and the silence/beat detectors expect.
    ///
    /// - Parameters:
    ///   - input: source video/audio file (anything ffmpeg reads).
    ///   - output: `.wav` destination.
    ///   - sampleRate: 16 kHz default balances detector precision and size.
    public func audioArguments(input: String, output: String,
                               sampleRate: Int = 16_000,
                               overwrite: Bool = true) -> [String] {
        var args: [String] = []
        if overwrite { args.append("-y") }
        args += ["-i", input,
                 "-vn",                      // drop video
                 "-ac", "1",                 // mono
                 "-ar", String(sampleRate),  // resample
                 "-c:a", "pcm_s16le",        // 16-bit PCM
                 output]
        return args
    }

    /// Downscaled grayscale frames for scene-change analysis, sampled at a
    /// fixed rate. `%06d` in the output pattern numbers the frames.
    public func framesArguments(input: String, outputPattern: String,
                                fps: Double = 5, height: Int = 90,
                                overwrite: Bool = true) -> [String] {
        var args: [String] = []
        if overwrite { args.append("-y") }
        args += ["-i", input,
                 "-vf", "fps=\(trimmed(fps)),scale=-2:\(height),format=gray",
                 "-an",
                 outputPattern]
        return args
    }

    public func audioCommandLine(input: String, output: String,
                                 sampleRate: Int = 16_000) -> String {
        display(audioArguments(input: input, output: output, sampleRate: sampleRate))
    }

    public func framesCommandLine(input: String, outputPattern: String,
                                  fps: Double = 5, height: Int = 90) -> String {
        display(framesArguments(input: input, outputPattern: outputPattern,
                                fps: fps, height: height))
    }

    private func display(_ args: [String]) -> String {
        ([executable] + args).map(FFmpegCommandBuilder.shellQuote).joined(separator: " ")
    }

    /// "5.0" → "5", "29.97" stays "29.97" — keeps filters canonical.
    private func trimmed(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(value)
    }
}
