import Foundation
import GhostlyCore
import GhostlyDetection
import GhostlyDirector

/// MCP tools over the real-audio pipeline: agents get the same powers as
/// `ghostly analyze-audio` and `ghostly edit --wav`. Audio is referenced by
/// file path — the MCP server runs on the user's machine next to the media.

/// `analyze_audio`: WAV file → speech ranges, beats/BPM, optional speakers.
public struct AnalyzeAudioTool: MCPTool {
    public let name = "analyze_audio"
    public let description = """
    Analyze a WAV audio file: speech ranges (for silence removal), beat \
    onsets and tempo, and — with diarize — who speaks when (S1, S2, …). \
    Use ffmpeg to convert other formats first (see extract-audio recipes).
    """
    public let inputSchema: JSONValue = .object([
        "type": "object",
        "properties": .object([
            "audioPath": .object(["type": "string", "description": "path to a .wav file"]),
            "diarize": .object(["type": "boolean", "description": "attribute speech ranges to speakers"]),
        ]),
        "required": .array(["audioPath"]),
    ])

    public init() {}

    public func call(arguments: JSONValue) async throws -> JSONValue {
        guard let path = arguments["audioPath"]?.stringValue, !path.isEmpty else {
            throw StudioError.invalidInput(field: "audioPath", reason: "required")
        }
        let audio = try WAV.decode(contentsOf: URL(fileURLWithPath: path))
        let speech = SilenceDetector().speechRanges(samples: audio.samples,
                                                    sampleRate: audio.sampleRate)
        let beats = BeatDetector().detect(samples: audio.samples,
                                          sampleRate: audio.sampleRate)

        var result: [String: JSONValue] = [
            "durationSeconds": .number(audio.duration.seconds),
            "sampleRate": .number(Double(audio.sampleRate)),
            "speechRanges": .array(speech.map(Self.range)),
            "beatSeconds": .array(beats.beats.map { .number($0.seconds) }),
            "bpm": beats.bpm.map(JSONValue.number) ?? .null,
        ]
        if arguments["diarize"]?.boolValue == true {
            let turns = SpeakerDiarizer().turns(samples: audio.samples,
                                                sampleRate: audio.sampleRate,
                                                speechRanges: speech)
            result["speakerCount"] = .number(Double(SpeakerDiarizer.speakerCount(turns)))
            result["speakerTurns"] = .array(turns.map { turn in
                .object([
                    "startSeconds": .number(turn.range.start.seconds),
                    "endSeconds": .number(turn.range.end.seconds),
                    "speaker": .string(turn.speaker),
                ])
            })
        }
        return .object(result)
    }

    static func range(_ range: TimeRange) -> JSONValue {
        .object(["startSeconds": .number(range.start.seconds),
                 "endSeconds": .number(range.end.seconds)])
    }
}

/// `edit_from_audio`: WAV file + command (+ optional transcript) → FCPXML.
public struct EditFromAudioTool: MCPTool {
    public let name = "edit_from_audio"
    public let description = """
    Auto-edit a real recording end-to-end: decode a WAV file, detect speech \
    and tempo, apply a natural-language editing command, optionally attach a \
    transcript as captions (language defaults to Thai, 'th'), optionally \
    diarize speakers onto the captions, and return validated FCPXML.
    """
    public let inputSchema: JSONValue = .object([
        "type": "object",
        "properties": .object([
            "audioPath": .object(["type": "string", "description": "path to a .wav file"]),
            "command": .object(["type": "string", "description": "natural-language editing instruction"]),
            "transcriptSRT": .object(["type": "string", "description": "optional SRT/VTT content for captions"]),
            "language": .object(["type": "string", "description": "caption language (BCP-47); default 'th'"]),
            "diarize": .object(["type": "boolean", "description": "tag captions with speakers (S1, S2, …)"]),
            "projectName": .object(["type": "string"]),
        ]),
        "required": .array(["audioPath", "command"]),
    ])

    public init() {}

    public func call(arguments: JSONValue) async throws -> JSONValue {
        guard let path = arguments["audioPath"]?.stringValue, !path.isEmpty else {
            throw StudioError.invalidInput(field: "audioPath", reason: "required")
        }
        guard let command = arguments["command"]?.stringValue, !command.isEmpty else {
            throw StudioError.invalidInput(field: "command", reason: "required")
        }
        let audio = try WAV.decode(contentsOf: URL(fileURLWithPath: path))
        let output = try EditPipeline.run(EditPipeline.AudioInput(
            audio: audio,
            subtitles: arguments["transcriptSRT"]?.stringValue,
            command: command,
            language: arguments["language"]?.stringValue ?? "th",
            clipName: (path as NSString).lastPathComponent,
            projectName: arguments["projectName"]?.stringValue ?? "AI Edit",
            diarize: arguments["diarize"]?.boolValue ?? false))
        guard output.isValid else {
            throw StudioError.validationFailure(detail: output.issues.joined(separator: "; "))
        }
        return .object([
            "fcpxml": .string(output.fcpxml),
            "clips": .number(Double(output.storylineClipCount)),
            "captions": .number(Double(output.captionCount)),
            "durationSeconds": .number(output.durationSeconds),
            "vertical": .bool(output.isVertical),
            "language": .string(output.language),
            "bpm": output.detectedBPM.map(JSONValue.number) ?? .null,
            "speakerCount": output.speakerCount.map { .number(Double($0)) } ?? .null,
        ])
    }
}
