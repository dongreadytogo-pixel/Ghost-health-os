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

    /// Splits long cues so none exceeds `maxCharactersPerLine` characters.
    /// Word-timed cues wrap on word boundaries (timings preserved); cues in
    /// spaceless scripts (Thai, CJK…) wrap by character, splitting the time
    /// range proportionally. Timed tokens are re-joined without inserting
    /// spaces for spaceless scripts, so Thai text is never mangled.
    public func wrapped(maxCharactersPerLine: Int) -> SubtitleTrack {
        var out: [SubtitleCue] = []
        for cue in cues {
            if cue.text.count <= maxCharactersPerLine {
                out.append(cue)
            } else if cue.words.count >= 2 {
                out.append(contentsOf: wrapByWords(cue, max: maxCharactersPerLine))
            } else {
                out.append(contentsOf: wrapPlainText(cue, max: maxCharactersPerLine))
            }
        }
        return SubtitleTrack(language: language, cues: out)
    }

    /// Wraps a word-timed cue on word boundaries. The join separator is empty
    /// for spaceless scripts so Thai/CJK tokens re-join into contiguous text.
    private func wrapByWords(_ cue: SubtitleCue, max maxCharactersPerLine: Int) -> [SubtitleCue] {
        let separator = TextScript.isSpaceless(cue.text) ? "" : " "
        let sepLength = separator.count
        var out: [SubtitleCue] = []
        var current: [SubtitleCue.TimedWord] = []
        var currentLength = 0
        func flush() {
            guard let first = current.first, let last = current.last else { return }
            out.append(SubtitleCue(
                range: TimeRange(start: first.range.start, end: last.range.end),
                text: current.map(\.text).joined(separator: separator),
                speaker: cue.speaker,
                words: current))
            current = []
            currentLength = 0
        }
        for word in cue.words {
            let projected = currentLength + word.text.count + (current.isEmpty ? 0 : sepLength)
            if projected > maxCharactersPerLine, !current.isEmpty {
                flush()
            }
            current.append(word)
            currentLength += word.text.count + (current.count > 1 ? sepLength : 0)
        }
        flush()
        return out
    }

    /// Wraps a cue that has no usable word timings. Spaceless scripts (Thai,
    /// CJK…) are chunked by grapheme; spaced text is packed on word boundaries
    /// so words are never broken. Each chunk is allocated a share of the cue's
    /// duration proportional to its character length.
    private func wrapPlainText(_ cue: SubtitleCue, max maxCharactersPerLine: Int) -> [SubtitleCue] {
        let chunks: [String] = TextScript.isSpaceless(cue.text)
            ? graphemeChunks(cue.text, max: maxCharactersPerLine)
            : packWords(cue.text, max: maxCharactersPerLine)
        guard chunks.count > 1 else { return [cue] }

        let lengths = chunks.map(\.count)
        let total = max(1, lengths.reduce(0, +))
        let start = cue.range.start
        let duration = cue.range.duration
        var out: [SubtitleCue] = []
        var consumed = 0
        for (chunk, length) in zip(chunks, lengths) {
            let sliceStart = start + duration.scaled(by: consumed, over: total)
            consumed += length
            let sliceEnd = start + duration.scaled(by: consumed, over: total)
            out.append(SubtitleCue(
                range: TimeRange(start: sliceStart, end: sliceEnd),
                text: chunk, speaker: cue.speaker))
        }
        return out
    }

    /// Fixed-size grapheme chunks (for spaceless scripts).
    private func graphemeChunks(_ text: String, max maxCharactersPerLine: Int) -> [String] {
        let chars = Array(text)
        var chunks: [String] = []
        var index = 0
        while index < chars.count {
            let end = Swift.min(index + maxCharactersPerLine, chars.count)
            chunks.append(String(chars[index..<end]))
            index = end
        }
        return chunks
    }

    /// Greedily packs whitespace-separated words into lines ≤ max (a single
    /// word longer than max becomes its own line rather than being split).
    private func packWords(_ text: String, max maxCharactersPerLine: Int) -> [String] {
        var lines: [String] = []
        var current = ""
        for word in text.split(whereSeparator: { $0 == " " || $0 == "\n" }) {
            if current.isEmpty {
                current = String(word)
            } else if current.count + 1 + word.count <= maxCharactersPerLine {
                current += " " + word
            } else {
                lines.append(current)
                current = String(word)
            }
        }
        if !current.isEmpty { lines.append(current) }
        return lines
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

    /// Returns a copy with every numeral in each cue read aloud in Thai
    /// (e.g. "ราคา 150 บาท" → "ราคา หนึ่งร้อยห้าสิบ บาท"). Word timings, being
    /// tied to the original tokens, are dropped for rewritten cues.
    public func verbalizingThaiNumbers() -> SubtitleTrack {
        SubtitleTrack(language: language, cues: cues.map { cue in
            let spoken = ThaiNumber.verbalize(cue.text)
            guard spoken != cue.text else { return cue }
            return SubtitleCue(range: cue.range, text: spoken, speaker: cue.speaker)
        })
    }

    /// Converts cues into FCP timeline captions, carrying the track's language
    /// (BCP-47) into each caption so the FCPXML role is tagged correctly
    /// (e.g. `ITT.th` for a Thai track).
    public func captions(format: Caption.CaptionFormat = .itt, styleName: String? = nil) -> [Caption] {
        cues.map { cue in
            Caption(text: cue.speaker.map { "\($0): \(cue.text)" } ?? cue.text,
                    range: cue.range, speaker: cue.speaker,
                    format: format, styleName: styleName, language: language)
        }
    }
}
