import Foundation
import GhostlyCore

/// SubRip (`.srt`) codec.
public enum SRT {
    /// Millisecond precision is the SRT wire format, so cues use a 1000 timescale.
    static let timescale: Int32 = 1000

    // MARK: Parse

    public static func parse(_ content: String) throws -> SubtitleTrack {
        let normalized = content
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\u{FEFF}", with: "")
        let blocks = normalized.components(separatedBy: "\n\n")
        var cues: [SubtitleCue] = []
        for block in blocks {
            let lines = block.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
            guard !lines.isEmpty else { continue }
            // Index line is optional in practice; find the timing line.
            guard let timingIndex = lines.firstIndex(where: { $0.contains("-->") }) else {
                if lines.allSatisfy({ Int($0.trimmingCharacters(in: .whitespaces)) != nil }) {
                    continue // stray index-only block
                }
                throw StudioError.parseFailure(format: "SRT", detail: "block without timing line: '\(lines[0])'")
            }
            let (start, end) = try parseTiming(lines[timingIndex])
            let textLines = lines[(timingIndex + 1)...]
            guard !textLines.isEmpty else { continue }
            var speaker: String?
            var text = textLines.joined(separator: "\n")
            // Common speaker convention: "NAME: line".
            if let colon = text.firstIndex(of: ":"),
               colon != text.startIndex,
               text[..<colon].count <= 24,
               !text[..<colon].contains("\n"),
               text[text.index(after: colon)...].first == " " {
                let candidate = String(text[..<colon])
                if candidate == candidate.uppercased() {
                    speaker = candidate
                    text = String(text[text.index(colon, offsetBy: 2)...])
                }
            }
            cues.append(SubtitleCue(range: TimeRange(start: start, end: end),
                                    text: text, speaker: speaker))
        }
        guard !cues.isEmpty else {
            throw StudioError.parseFailure(format: "SRT", detail: "no cues found")
        }
        return SubtitleTrack(cues: cues)
    }

    static func parseTiming(_ line: String) throws -> (RationalTime, RationalTime) {
        let parts = line.components(separatedBy: "-->")
        guard parts.count == 2,
              let start = parseTimestamp(parts[0].trimmingCharacters(in: .whitespaces)),
              let end = parseTimestamp(parts[1].trimmingCharacters(in: .whitespaces)
                .components(separatedBy: " ").first ?? ""),
              end >= start else {
            throw StudioError.parseFailure(format: "SRT", detail: "bad timing line: '\(line)'")
        }
        return (start, end)
    }

    /// `HH:MM:SS,mmm` (also tolerates `.` as the millisecond separator).
    static func parseTimestamp(_ string: String) -> RationalTime? {
        let cleaned = string.replacingOccurrences(of: ".", with: ",")
        let major = cleaned.components(separatedBy: ",")
        guard major.count == 2, let millis = Int64(major[1]), millis < 1000 else { return nil }
        let hms = major[0].components(separatedBy: ":").compactMap { Int64($0) }
        guard hms.count == 3, hms[1] < 60, hms[2] < 60 else { return nil }
        let seconds = hms[0] * 3600 + hms[1] * 60 + hms[2]
        return RationalTime(value: seconds * 1000 + millis, timescale: timescale)
    }

    // MARK: Serialize

    public static func serialize(_ track: SubtitleTrack) -> String {
        var blocks: [String] = []
        for (index, cue) in track.cues.enumerated() {
            let text = cue.speaker.map { "\($0): \(cue.text)" } ?? cue.text
            blocks.append("""
            \(index + 1)
            \(timestamp(cue.range.start)) --> \(timestamp(cue.range.end))
            \(text)
            """)
        }
        return blocks.joined(separator: "\n\n") + "\n"
    }

    static func timestamp(_ time: RationalTime) -> String {
        let totalMillis = max(0, Int64((time.seconds * 1000).rounded()))
        let h = totalMillis / 3_600_000
        let m = (totalMillis / 60_000) % 60
        let s = (totalMillis / 1000) % 60
        let ms = totalMillis % 1000
        return String(format: "%02d:%02d:%02d,%03d", h, m, s, ms)
    }
}

/// WebVTT (`.vtt`) codec.
public enum WebVTT {
    public static func parse(_ content: String) throws -> SubtitleTrack {
        let normalized = content
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\u{FEFF}", with: "")
        guard normalized.hasPrefix("WEBVTT") else {
            throw StudioError.parseFailure(format: "WebVTT", detail: "missing WEBVTT header")
        }
        // VTT uses `.` for millis; convert timing lines and reuse SRT parsing.
        var cues: [SubtitleCue] = []
        for block in normalized.components(separatedBy: "\n\n").dropFirst() {
            let lines = block.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
            guard let timingIndex = lines.firstIndex(where: { $0.contains("-->") }) else { continue }
            guard lines.count > timingIndex + 1 else { continue }
            let timingLine = normalizeTimestamps(lines[timingIndex])
            let (start, end) = try SRT.parseTiming(timingLine)
            let text = lines[(timingIndex + 1)...].joined(separator: "\n")
                .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            cues.append(SubtitleCue(range: TimeRange(start: start, end: end), text: text))
        }
        guard !cues.isEmpty else {
            throw StudioError.parseFailure(format: "WebVTT", detail: "no cues found")
        }
        return SubtitleTrack(cues: cues)
    }

    /// VTT allows `MM:SS.mmm` (no hours); SRT parsing requires `HH:MM:SS,mmm`.
    private static func normalizeTimestamps(_ line: String) -> String {
        line.components(separatedBy: "-->").map { part in
            var stamp = part.trimmingCharacters(in: .whitespaces)
                .components(separatedBy: " ").first ?? ""
            if stamp.components(separatedBy: ":").count == 2 { stamp = "00:" + stamp }
            return stamp
        }.joined(separator: " --> ")
    }

    public static func serialize(_ track: SubtitleTrack) -> String {
        var out = "WEBVTT\n\n"
        out += track.cues.map { cue in
            let start = SRT.timestamp(cue.range.start).replacingOccurrences(of: ",", with: ".")
            let end = SRT.timestamp(cue.range.end).replacingOccurrences(of: ",", with: ".")
            let text = cue.speaker.map { "<v \($0)>\(cue.text)" } ?? cue.text
            return "\(start) --> \(end)\n\(text)"
        }.joined(separator: "\n\n")
        out += "\n"
        return out
    }
}
