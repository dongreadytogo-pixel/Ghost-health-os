import Foundation

/// Script-level text facts the subtitle engine needs to treat non-Latin
/// languages correctly. The key distinction for captioning is whether a
/// script writes words **without** spaces between them (Thai, Lao, Khmer,
/// Burmese, CJK, Japanese kana, Korean written without spaces): such text
/// must be wrapped by character, not by splitting on spaces, and timed
/// tokens must be re-joined without inserting spurious spaces.
public enum TextScript {
    /// True when the text is written in a script that lacks inter-word spaces.
    public static func isSpaceless(_ text: String) -> Bool {
        for scalar in text.unicodeScalars where isSpacelessScalar(scalar.value) {
            return true
        }
        return false
    }

    /// True when the text contains at least one Latin letter (used to decide
    /// whether Latin-style capitalization/punctuation is meaningful).
    public static func hasLatinLetters(_ text: String) -> Bool {
        text.unicodeScalars.contains { scalar in
            let v = scalar.value
            return (0x41...0x5A).contains(v) || (0x61...0x7A).contains(v)
        }
    }

    private static func isSpacelessScalar(_ v: UInt32) -> Bool {
        (0x0E00...0x0E7F).contains(v)   // Thai
            || (0x0E80...0x0EFF).contains(v)   // Lao
            || (0x1780...0x17FF).contains(v)   // Khmer
            || (0x1000...0x109F).contains(v)   // Myanmar
            || (0x3040...0x30FF).contains(v)   // Hiragana + Katakana
            || (0x4E00...0x9FFF).contains(v)   // CJK Unified Ideographs
            || (0xAC00...0xD7AF).contains(v)   // Hangul syllables
    }
}
