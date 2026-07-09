import Foundation
import GhostlyCore
import GhostlySubtitles

/// Speech-to-text port: audio in, a word-timed `SubtitleTrack` out. Backends:
/// whisper.cpp (below), Apple `SFSpeechRecognizer` (planned), cloud ASR.
public protocol Transcribing: Sendable {
    /// - Parameters:
    ///   - url: audio (or video) file to transcribe.
    ///   - language: BCP-47 hint (e.g. "th"); nil = auto-detect.
    func transcribe(_ url: URL, language: String?) async throws -> SubtitleTrack
}

/// Parses whisper.cpp's full-JSON output (`--output-json-full` / `-ojf`) into
/// a word-timed `SubtitleTrack`. Pure and cross-platform — fixture-tested on
/// CI without a Whisper binary. Millisecond `offsets` are used (not the
/// formatted timestamps) so timing stays exact.
public enum WhisperJSONParser {
    // whisper.cpp JSON shape (subset we consume).
    private struct Output: Decodable {
        struct Result: Decodable { var language: String? }
        struct Offsets: Decodable { var from: Int64; var to: Int64 }
        struct Token: Decodable {
            var text: String
            var offsets: Offsets?
            var p: Double?
        }
        struct Segment: Decodable {
            var offsets: Offsets
            var text: String
            var tokens: [Token]?
        }
        var result: Result?
        var transcription: [Segment]
    }

    /// - Parameters:
    ///   - data: whisper.cpp JSON file contents.
    ///   - languageHint: used when the JSON carries no detected language.
    public static func track(from data: Data, languageHint: String? = nil) throws -> SubtitleTrack {
        let output: Output
        do {
            output = try JSONDecoder().decode(Output.self, from: data)
        } catch {
            throw StudioError.parseFailure(format: "whisper JSON",
                                           detail: "not a whisper.cpp full-JSON file")
        }
        let language = output.result?.language ?? languageHint ?? "en"

        var cues: [SubtitleCue] = []
        for segment in output.transcription {
            let text = segment.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty, segment.offsets.to > segment.offsets.from else { continue }
            let range = TimeRange(start: time(ms: segment.offsets.from),
                                  end: time(ms: segment.offsets.to))
            let words: [SubtitleCue.TimedWord] = (segment.tokens ?? []).compactMap { token in
                let word = token.text.trimmingCharacters(in: .whitespaces)
                guard !word.isEmpty, !isSpecialToken(word),
                      let offsets = token.offsets, offsets.to > offsets.from else { return nil }
                return SubtitleCue.TimedWord(
                    text: word,
                    range: TimeRange(start: time(ms: offsets.from), end: time(ms: offsets.to)))
            }
            cues.append(SubtitleCue(range: range, text: text, words: words))
        }
        guard !cues.isEmpty else {
            throw StudioError.parseFailure(format: "whisper JSON", detail: "no transcription segments")
        }
        return SubtitleTrack(language: language, cues: cues)
    }

    /// Whisper control tokens like `[_BEG_]`, `[_TT_42]`, `<|endoftext|>`.
    static func isSpecialToken(_ text: String) -> Bool {
        (text.hasPrefix("[_") && text.hasSuffix("]"))
            || (text.hasPrefix("<|") && text.hasSuffix("|>"))
    }

    private static func time(ms: Int64) -> RationalTime {
        RationalTime(value: ms, timescale: 1000)
    }
}

/// Runs a whisper.cpp CLI binary and parses its JSON output. The process
/// launch is injectable so the wrapper's argument construction and JSON
/// handling are tested without a real binary; on a Mac with whisper.cpp
/// installed this is the production Thai/multilingual ASR path.
public struct WhisperCLITranscriber: Transcribing {
    /// Runs the command, returning the produced JSON file's contents.
    public typealias Runner = @Sendable (_ arguments: [String], _ jsonOutputPath: String) async throws -> Data

    public var executablePath: String
    public var modelPath: String
    private let runner: Runner

    public init(executablePath: String = "whisper-cli", modelPath: String,
                runner: Runner? = nil) {
        self.executablePath = executablePath
        self.modelPath = modelPath
        self.runner = runner ?? Self.processRunner(executablePath: executablePath)
    }

    /// The exact argument vector passed to whisper.cpp.
    public func arguments(for url: URL, language: String?, jsonBase: String) -> [String] {
        var args = ["-m", modelPath, "-f", url.path,
                    "--output-json-full", "--output-file", jsonBase,
                    "--max-len", "1"] // token-level timestamps
        if let language { args += ["-l", language] }
        return args
    }

    public func transcribe(_ url: URL, language: String?) async throws -> SubtitleTrack {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("ghostly-whisper-\(UUID().uuidString)").path
        let data = try await runner(arguments(for: url, language: language, jsonBase: base),
                                    base + ".json")
        return try WhisperJSONParser.track(from: data, languageHint: language)
    }

    // MARK: Default process-based runner (desktop platforms)

    static func processRunner(executablePath: String) -> Runner {
        { arguments, jsonOutputPath in
            #if os(macOS) || os(Linux)
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = [executablePath] + arguments
            let stderrPipe = Pipe()
            process.standardError = stderrPipe
            process.standardOutput = Pipe()
            do {
                try process.run()
            } catch {
                throw StudioError.io(path: executablePath,
                    detail: "cannot launch whisper (\(error.localizedDescription)); install whisper.cpp or pass a custom runner")
            }
            process.waitUntilExit()
            guard process.terminationStatus == 0 else {
                let err = String(data: stderrPipe.fileHandleForReading.readDataToEndOfFile(),
                                 encoding: .utf8) ?? ""
                throw StudioError.io(path: executablePath,
                                     detail: "whisper exited \(process.terminationStatus): \(err.suffix(300))")
            }
            do {
                return try Data(contentsOf: URL(fileURLWithPath: jsonOutputPath))
            } catch {
                throw StudioError.io(path: jsonOutputPath,
                                     detail: "whisper produced no JSON output")
            }
            #else
            throw StudioError.unsupportedPlatform(operation: "whisper.cpp transcription")
            #endif
        }
    }
}
