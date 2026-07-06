import Foundation
import GhostlyCore

/// Adds light punctuation and capitalization to raw transcript text — the
/// kind of cleanup ASR output (Whisper without punctuation, or word-timed
/// streams) needs before it reads like captions (Phase 6).
///
/// Deterministic and rule-based: capitalizes sentence starts and the pronoun
/// "I", capitalizes an explicit set of proper nouns, appends terminal
/// punctuation to cues that lack it, and adds "?" when a cue opens with a
/// question word. It is intentionally conservative — it never removes text.
public struct AutoPunctuator: Sendable {
    /// Words that, when they open a cue, mark it as a question.
    private static let questionOpeners: Set<String> = [
        "who", "what", "when", "where", "why", "how", "which", "whose", "whom",
        "is", "are", "am", "do", "does", "did", "can", "could", "would", "should",
        "will", "shall", "may", "might", "have", "has", "had",
    ]

    /// Proper nouns to always capitalize (case-insensitive match).
    public var properNouns: Set<String>

    public init(properNouns: Set<String> = []) {
        self.properNouns = Set(properNouns.map { $0.lowercased() })
    }

    /// Punctuates and capitalizes a single line of text.
    public func punctuate(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return text }

        // Latin-style capitalization and terminal "." / "?" are meaningless for
        // scripts like Thai (no letter case, different punctuation norms), so
        // leave such text untouched rather than corrupting it.
        guard TextScript.hasLatinLetters(trimmed) else { return text }

        // Capitalize word-by-word: sentence starts, "I", and known nouns.
        var capitalizeNext = true
        var words: [String] = []
        for rawWord in trimmed.split(separator: " ", omittingEmptySubsequences: true) {
            var word = String(rawWord)
            let lower = word.lowercased()
            let bareLower = lower.trimmingCharacters(in: CharacterSet(charactersIn: ".,!?;:"))

            if capitalizeNext || bareLower == "i" || properNouns.contains(bareLower) {
                word = capitalizeFirstLetter(word)
            }
            words.append(word)
            // Next word is a sentence start if this one ended a sentence.
            capitalizeNext = word.hasSuffix(".") || word.hasSuffix("!") || word.hasSuffix("?")
        }

        var result = words.joined(separator: " ")

        // Terminal punctuation.
        if let last = result.unicodeScalars.last, !".!?".unicodeScalars.contains(last) {
            let firstWord = (words.first ?? "").lowercased()
                .trimmingCharacters(in: CharacterSet(charactersIn: ".,!?;:"))
            result += Self.questionOpeners.contains(firstWord) ? "?" : "."
        }
        return result
    }

    /// Punctuates every cue in a track, preserving all timing.
    public func punctuate(_ track: SubtitleTrack) -> SubtitleTrack {
        SubtitleTrack(language: track.language, cues: track.cues.map { cue in
            var punctuated = cue
            punctuated.text = punctuate(cue.text)
            return punctuated
        })
    }

    private func capitalizeFirstLetter(_ word: String) -> String {
        guard let first = word.first else { return word }
        return String(first).uppercased() + word.dropFirst()
    }
}
