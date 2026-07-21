import Foundation
import GhostlyCore

/// Sentence grouping for ASR output (Workflow Constitution v5 — "Proper
/// sentence grouping"): word-level transcription (whisper `--max-len 1`)
/// yields one cue per word, unreadable as subtitles. This merges fragments
/// into natural sentence-sized cues using the two signals Thai actually
/// provides — pauses between words and sentence-final particles
/// (ครับ/ค่ะ/คะ/จ้า/นะคะ…) — since Thai writes no full stops.
extension SubtitleTrack {
    /// Merges consecutive cues into sentence groups.
    ///
    /// A boundary opens between two cues when any of these holds:
    /// - the silence gap between them reaches `pauseSeconds` (a breath),
    /// - the group already ends with a sentence-final particle (or `.?!`)
    ///   and the gap reaches `particlePauseSeconds` (a short beat after
    ///   "ครับ" ends the sentence; mid-greeting "สวัสดีครับทุกคน" with no
    ///   gap stays together),
    /// - adding the cue would push the group past `maxCharactersPerCue`
    ///   (readability cap; the styles' wrapper splits lines later).
    ///
    /// Thai fragments re-join without spaces, spaced scripts with one space;
    /// word timings concatenate; the group spans first start → last end.
    public func groupedIntoSentences(pauseSeconds: Double = 0.6,
                                     particlePauseSeconds: Double = 0.25,
                                     maxCharactersPerCue: Int = 60) -> SubtitleTrack {
        guard cues.count > 1 else { return self }

        var grouped: [SubtitleCue] = []
        var current = cues[0]

        for cue in cues.dropFirst() {
            let gap = (cue.range.start - current.range.end).seconds
            let sentenceEnded = Self.endsSentence(current.text)
            let wouldOverflow = current.text.count + cue.text.count > maxCharactersPerCue
            let speakerChanged = cue.speaker != current.speaker

            if gap >= pauseSeconds
                || (sentenceEnded && gap >= particlePauseSeconds)
                || wouldOverflow
                || speakerChanged {
                grouped.append(current)
                current = cue
            } else {
                current = Self.merged(current, cue)
            }
        }
        grouped.append(current)
        return SubtitleTrack(language: language, cues: grouped)
    }

    /// Sentence-final detection: Thai polite/final particles or terminal
    /// punctuation from mixed English.
    static func endsSentence(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if let last = trimmed.last, ".?!।".contains(last) { return true }
        let particles = ["ครับ", "ครับผม", "ค่ะ", "คะ", "นะคะ", "นะครับ",
                         "จ้า", "จ้ะ", "ฮะ", "ครัช"]
        return particles.contains { trimmed.hasSuffix($0) }
    }

    private static func merged(_ a: SubtitleCue, _ b: SubtitleCue) -> SubtitleCue {
        // Thai↔Thai joins tight; anything involving a spaced script gets a
        // space (mixed Thai-English speech keeps the English readable).
        let separator = TextScript.isSpaceless(String(a.text.suffix(1)))
            && TextScript.isSpaceless(String(b.text.prefix(1))) ? "" : " "
        return SubtitleCue(
            range: TimeRange(start: a.range.start, end: b.range.end),
            text: a.text + separator + b.text,
            speaker: a.speaker,
            words: a.words + b.words)
    }
}
