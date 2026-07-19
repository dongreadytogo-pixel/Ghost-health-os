import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif
#if canImport(NaturalLanguage)
import NaturalLanguage
#endif
import GhostlyCore
import GhostlySubtitles

/// SUBTITLE Cover — ported 1:1 from the battle-tested Python original
/// (cover_subtitles.py v1.3, see docs/knowledge/SUBTITLE-COVER.md): reads a
/// project exported from Final Cut Pro, finds the editor's existing plain
/// subtitles (non-bold titles), smart-splits each into two lines (white top /
/// orange bottom, keywords pushed to the orange line), and layers pop-up
/// highlight titles above them at the exact same times — the originals are
/// never touched. Every constant below was calibrated against real FCP
/// output; do not "clean them up".
public enum SubtitleCover {
    // MARK: Calibrated constants (from real FCP exports — do not re-derive)

    static let cWhite = "0.999995 1 1 1"
    static let cOrange = "0.972616 0.300689 0.0428142 1"
    static let globalPos = "0.497087 0.378268"
    static let xWhite = "6.5699"
    static let xOrange = "6.8484"
    /// Orange line's bottom edge sits just above the original subtitle.
    static let bottomEdge = 55.0
    /// Single-line pop-ups ride higher, centered in the highlight zone.
    static let singleRaise = 60.0
    /// Half line-height per 1 pt of font size (calibrated: 73/71 pt pair
    /// measured 103 units apart in a hand-made reference project).
    static let lineHalf = 0.58
    /// Constant visual pad between the two lines — identical on every shot.
    static let gapPad = 6.0
    static let fillWidth = 1150.0
    static let maxUnits = 1170.0
    static let sizeMax = 120
    static let hardMin = 32
    static let balanceRatio = 1.9
    static let laneWhite = 10
    static let laneOrange = 11
    static let shortMaxChars = 10

    static let anchorable: Set<String> = ["clip", "asset-clip", "ref-clip", "mc-clip",
                                          "sync-clip", "gap", "video", "audio", "title"]
    static let filters: Set<String> = ["filter-video", "filter-audio", "marker", "chapter-marker",
                                       "rating", "keyword", "analysis-marker", "metadata"]

    /// Impact/benefit words (health-review vocabulary) pulled to the orange line.
    static let keywords = ["หายขาด", "หาย", "ดีขึ้น", "ไม่ปวด", "ไม่มี", "สดชื่น", "แข็งแรง", "มะเร็ง",
                           "เบาหวาน", "ริดสีดวง", "นอนหลับ", "คล่อง", "เยี่ยม", "คุ้ม", "ปลอดภัย",
                           "สำคัญ", "ต้องการ", "จำเป็น", "ที่สุด", "มากๆ", "ดีมาก", "หมดไป"]
    static let kwBonus = 6
    /// Short directional verbs/connectives that must not end the top line.
    static let noTrailWords: Set<String> = ["เข้า", "ออก", "ไป", "มา", "ขึ้น", "ลง", "กลับ", "ผ่าน", "ถึง", "ไว้", "อยู่",
                                            "ได้", "ต้อง", "จะ", "ก็", "แต่", "ให้", "เป็น", "มี", "ไม่", "คือ", "ว่า",
                                            "ที่", "ซึ่ง", "และ", "หรือ", "จาก", "ตาม", "กับ", "ของ", "ใน", "บน", "ใต้",
                                            "ก่อน", "จน", "เพื่อ", "โดย", "อย่าง", "พอ", "ทั้ง", "ยัง", "ค่อย", "เพิ่ง"]
    static let trailPenalty = 30
    /// Trailing particles that must not begin the bottom line.
    static let noLeadWords: Set<String> = ["ปุ๊บ", "ปั๊บ", "ครับ", "ค่ะ", "คะ", "นะ", "จ้ะ", "จ้า", "ล่ะ", "สิ", "ฮะ",
                                           "เนอะ", "เลย", "ด้วย", "อยู่", "แล้ว", "ไป", "มา", "ๆ"]
    static let leadPenalty = 30
    static let spaceBonus = 8

    // MARK: Results

    public struct Pair: Sendable, Equatable {
        public let index: Int
        public let white: String
        public let whiteSize: Int
        public let orange: String
        public let orangeSize: Int
    }

    public struct Output: Sendable {
        public let coverCount: Int
        public let outPath: String
        public let pairs: [Pair]
    }

    // MARK: Text helpers (lengths use unicode scalars — the Python `len`
    // the layout constants were calibrated against)

    static func charLen(_ s: String) -> Int { s.unicodeScalars.count }

    static func scalarPrefix(_ s: String, _ n: Int) -> String {
        String(String.UnicodeScalarView(s.unicodeScalars.prefix(n)))
    }

    /// Word tokens: Apple's NLTokenizer where available (true Thai word
    /// boundaries), Thai syllable break-units elsewhere — both are safe
    /// "never split a cluster" boundaries.
    static func tokens(_ text: String) -> [String] {
        #if canImport(NaturalLanguage)
        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = text
        var out: [String] = []
        var cursor = text.startIndex
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            if cursor < range.lowerBound {
                out.append(String(text[cursor..<range.lowerBound]))
            }
            out.append(String(text[range]))
            cursor = range.upperBound
            return true
        }
        if cursor < text.endIndex { out.append(String(text[cursor...])) }
        return out.isEmpty ? ThaiSegmentation.breakUnits(text) : out
        #else
        return ThaiSegmentation.breakUnits(text)
        #endif
    }

    /// Scalar positions that are token edges per the given tokenization.
    static func tokenEnds(_ toks: [String]) -> Set<Int> {
        var ends = Set<Int>()
        var pos = 0
        for t in toks {
            pos += charLen(t)
            ends.insert(pos)
        }
        return ends
    }

    static func lastWordBefore(_ toks: [String], cut: Int) -> String {
        var pos = 0
        for t in toks {
            pos += charLen(t)
            if pos == cut { return t.trimmingCharacters(in: .whitespaces) }
        }
        return ""
    }

    /// Smart two-line split — identical scoring to the original: balance,
    /// keyword pull to the orange line, space bonus, no-trail / no-lead
    /// penalties. Short sentences stay single-line (orange).
    public static func splitTwo(_ raw: String) -> (white: String, orange: String) {
        let text = raw.split(separator: " ").joined(separator: " ")
        guard charLen(text) > shortMaxChars else { return ("", text) }

        let wordToks = tokens(text)
        let syllToks = ThaiSegmentation.breakUnits(text)
        // Safe cuts: where both tokenizations agree — plus always after spaces.
        var agree = tokenEnds(wordToks).intersection(tokenEnds(syllToks))
        let scalars = Array(text.unicodeScalars)
        for (i, ch) in scalars.enumerated() where ch == " " { agree.insert(i + 1) }
        var cuts = agree.filter { $0 > 0 && $0 < scalars.count }.sorted()
        if cuts.isEmpty {
            cuts = tokenEnds(wordToks).filter { $0 > 0 && $0 < scalars.count }.sorted()
        }
        guard !cuts.isEmpty else { return ("", text) }

        var best: (score: Int, a: String, b: String)?
        for c in cuts {
            let a = String(String.UnicodeScalarView(scalars[0..<c])).trimmingCharacters(in: .whitespaces)
            let b = String(String.UnicodeScalarView(scalars[c...])).trimmingCharacters(in: .whitespaces)
            guard !a.isEmpty, !b.isEmpty else { continue }
            var score = abs(charLen(a) - charLen(b))
            if isKey(b) { score -= kwBonus }
            if scalars[c - 1] == " " || (c < scalars.count && scalars[c] == " ") { score -= spaceBonus }
            if noTrailWords.contains(lastWordBefore(wordToks, cut: c)) { score += trailPenalty }
            if noLeadWords.contains(where: { b.hasPrefix($0) }) { score += leadPenalty }
            if best == nil || score < best!.score { best = (score, a, b) }
        }
        guard let best else { return ("", text) }
        return (best.a, best.b)
    }

    static func isKey(_ orange: String) -> Bool {
        let o = orange.trimmingCharacters(in: .whitespaces)
        guard let first = o.unicodeScalars.first else { return false }
        return CharacterSet.decimalDigits.contains(first) || keywords.contains { o.hasPrefix($0) }
    }

    /// Font size: fill the frame but never overflow (hard cap `maxUnits`).
    public static func fit(_ line: String) -> Int {
        let n = max(charLen(line), 1)
        var s = min(sizeMax, Int(fillWidth / Double(n)))
        while s > hardMin && Double(n * s) > maxUnits { s -= 1 }
        return max(hardMin, s)
    }

    /// Cap the larger of the two sizes so the pair looks balanced.
    public static func balance(_ sw: Int, _ so: Int) -> (Int, Int) {
        let hi = max(sw, so), lo = min(sw, so)
        guard lo > 0, Double(hi) / Double(lo) > balanceRatio else { return (sw, so) }
        let capped = max(hardMin, Int(Double(lo) * balanceRatio))
        return sw > so ? (capped, so) : (sw, capped)
    }

    // MARK: FCPXML time helpers

    static func seconds(_ s: String?) -> Double {
        guard var v = s?.trimmingCharacters(in: .whitespaces), !v.isEmpty else { return 0 }
        if v.hasSuffix("s") { v.removeLast() }
        if v.contains("/") {
            let parts = v.split(separator: "/")
            guard parts.count == 2, let a = Double(parts[0]), let b = Double(parts[1]), b != 0 else { return 0 }
            return a / b
        }
        return Double(v) ?? 0
    }

    static func rational(_ sec: Double, timebase: Int) -> String {
        "\(Int((sec * Double(timebase)).rounded()))/\(timebase)s"
    }

    static func safeName(_ s: String?) -> String {
        let bad = Set("/\\:*?\"<>|")
        let cleaned = (s ?? "").filter { !bad.contains($0) }.trimmingCharacters(in: .whitespaces)
        return cleaned.isEmpty ? "project" : cleaned
    }
}
