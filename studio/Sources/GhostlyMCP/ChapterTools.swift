import Foundation
import GhostlyCore
import GhostlyDomain
import GhostlyDetection
import GhostlySubtitles
import GhostlyDirector

/// `export_chapters`: transcript + duration → the YouTube chapter block a
/// creator pastes into a video description. Same engine as `ghostly chapters`.
public struct ExportChaptersTool: MCPTool {
    public let name = "export_chapters"
    public let description = """
    Turn a transcript (SRT/VTT) plus the video duration into the YouTube \
    chapter block for the video description ("0:00 บทนำ" lines, one per \
    chapter, titles taken from the transcript). Enforces YouTube's rules \
    (first chapter at 0:00, at least 3 chapters, each ≥10 s): when they \
    can't be met the result has valid=false and a Thai reason instead.
    """
    public let inputSchema: JSONValue = .object([
        "type": "object",
        "properties": .object([
            "transcriptSRT": .object(["type": "string", "description": "SRT or VTT content"]),
            "durationSeconds": .object(["type": "number", "description": "video length in seconds"]),
            "language": .object(["type": "string", "description": "BCP-47 transcript language; default 'th'"]),
        ]),
        "required": .array(["transcriptSRT", "durationSeconds"]),
    ])

    public init() {}

    public func call(arguments: JSONValue) async throws -> JSONValue {
        guard let srt = arguments["transcriptSRT"]?.stringValue, !srt.isEmpty else {
            throw StudioError.invalidInput(field: "transcriptSRT", reason: "required")
        }
        guard let seconds = arguments["durationSeconds"]?.numberValue, seconds > 0 else {
            throw StudioError.invalidInput(field: "durationSeconds", reason: "must be positive")
        }
        let parsed = srt.hasPrefix("WEBVTT") ? try WebVTT.parse(srt) : try SRT.parse(srt)
        let transcript = SubtitleTrack(language: arguments["language"]?.stringValue ?? "th",
                                       cues: parsed.cues)
        let duration = RationalTime(seconds: seconds, preferredTimescale: 3000)
        // Cue timings double as speech ranges, exactly like `ghostly chapters`.
        let asset = Asset(name: "video", url: URL(fileURLWithPath: "/media/video"),
                          duration: duration, kind: .video)
        let analysis = MediaAnalysis(assetID: asset.id, duration: duration,
                                     speechRanges: parsed.cues.map(\.range))
        let markers = HighlightPlanner().chapters(from: analysis, transcript: transcript)
        guard let text = ChapterExport.youTubeDescription(markers: markers, duration: duration) else {
            return .object([
                "valid": .bool(false),
                "reason": .string("YouTube ต้องมีอย่างน้อย 3 บท เริ่มที่ 0:00 และแต่ละบทยาว ≥ 10 วินาที"),
            ])
        }
        return .object([
            "valid": .bool(true),
            "description": .string(text),
            "chapterCount": .number(Double(markers.filter { $0.kind == .chapter }.count)),
        ])
    }
}
