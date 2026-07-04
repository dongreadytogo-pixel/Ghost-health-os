import Foundation
import GhostlyCore
import GhostlyDomain

/// A single subtitle cue with optional word-level timing (as produced by
/// Whisper-style transcribers), which powers karaoke/animated captions.
public struct SubtitleCue: Hashable, Sendable, Codable {
    public var range: TimeRange
    public var text: String
    public var speaker: String?
    public var words: [TimedWord]

    public struct TimedWord: Hashable, Sendable, Codable {
        public var text: String
        public var range: TimeRange

        public init(text: String, range: TimeRange) {
            self.text = text
            self.range = range
        }
    }

    public init(range: TimeRange, text: String, speaker: String? = nil, words: [TimedWord] = []) {
        self.range = range
        self.text = text
        self.speaker = speaker
        self.words = words
    }
}

/// An ordered subtitle track.
public struct SubtitleTrack: Sendable, Codable {
    public var language: String
    public var cues: [SubtitleCue]

    public init(language: String = "en", cues: [SubtitleCue] = []) {
        self.language = language
        self.cues = cues.sorted { $0.range.start < $1.range.start }
    }

    public var duration: RationalTime { cues.map(\.range.end).max() ?? .zero }

    /// Splits long cues so none exceeds `maxCharactersPerLine` characters —
    /// respecting word timings when present so re-timing stays accurate.
    public func wrapped(maxCharactersPerLine: Int) -> SubtitleTrack {
        var out: [SubtitleCue] = []
        for cue in cues {
            if cue.text.count <= maxCharactersPerLine || cue.words.count < 2 {
                out.append(cue)
                continue
            }
            var current: [SubtitleCue.TimedWord] = []
            var currentLength = 0
            func flush() {
                guard let first = current.first, let last = current.last else { return }
                out.append(SubtitleCue(
                    range: TimeRange(start: first.range.start, end: last.range.end),
                    text: current.map(\.text).joined(separator: " "),
                    speaker: cue.speaker,
                    words: current))
                current = []
                currentLength = 0
            }
            for word in cue.words {
                let projected = currentLength + word.text.count + (current.isEmpty ? 0 : 1)
                if projected > maxCharactersPerLine, !current.isEmpty {
                    flush()
                }
                current.append(word)
                currentLength += word.text.count + (current.count > 1 ? 1 : 0)
            }
            flush()
        }
        return SubtitleTrack(language: language, cues: out)
    }

    /// Shifts all cues by a signed offset (e.g. to align to a clip's position).
    public func shifted(by offset: RationalTime) -> SubtitleTrack {
        SubtitleTrack(language: language, cues: cues.map { cue in
            var moved = cue
            moved.range.start = cue.range.start + offset
            moved.words = cue.words.map { word in
                var w = word
                w.range.start = word.range.start + offset
                return w
            }
            return moved
        })
    }

    /// Converts cues into FCP timeline captions.
    public func captions(format: Caption.CaptionFormat = .itt, styleName: String? = nil) -> [Caption] {
        cues.map { cue in
            Caption(text: cue.speaker.map { "\($0): \(cue.text)" } ?? cue.text,
                    range: cue.range, speaker: cue.speaker,
                    format: format, styleName: styleName)
        }
    }
}
