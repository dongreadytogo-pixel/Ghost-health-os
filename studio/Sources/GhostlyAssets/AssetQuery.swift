import Foundation
import GhostlyCore
import GhostlyDomain

/// A structured asset filter parsed from a natural-language query such as
/// "vertical 4k drone clips under 30 seconds" or "favorite interview audio".
/// Deterministic and offline — the studio's natural-language asset search
/// without needing a model in the loop.
public struct AssetQuery: Sendable, Equatable {
    public var kinds: Set<Asset.Kind>
    public var requiredTags: Set<String>
    public var freeTextTerms: [String]
    public var favoritesOnly: Bool
    /// Inclusive duration bounds in seconds, if constrained.
    public var maxDuration: Double?
    public var minDuration: Double?
    public var verticalOnly: Bool
    public var horizontalOnly: Bool

    public init(kinds: Set<Asset.Kind> = [], requiredTags: Set<String> = [],
                freeTextTerms: [String] = [], favoritesOnly: Bool = false,
                maxDuration: Double? = nil, minDuration: Double? = nil,
                verticalOnly: Bool = false, horizontalOnly: Bool = false) {
        self.kinds = kinds
        self.requiredTags = requiredTags
        self.freeTextTerms = freeTextTerms
        self.favoritesOnly = favoritesOnly
        self.maxDuration = maxDuration
        self.minDuration = minDuration
        self.verticalOnly = verticalOnly
        self.horizontalOnly = horizontalOnly
    }

    /// Parses a free-form query — English or Thai ("หาคลิปแมวตอนกลางคืน").
    /// Recognizes kinds, favorite/vertical/horizontal keywords, and
    /// "under/over N seconds/minutes" / "ไม่เกิน 30 วินาที" duration bounds;
    /// every remaining word becomes a free-text term matched against the
    /// asset's name and tags (with Thai↔English synonym expansion).
    public init(parsing query: String) {
        var q = AssetQuery()
        let lower = query.lowercased()
        let words = lower.components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }

        // Kinds (English + Thai).
        if ["video", "clip", "footage", "วิดีโอ", "คลิป", "ฟุตเทจ"].contains(where: lower.contains) {
            q.kinds.insert(.video)
        }
        if ["audio", "music", "sound", "เสียง", "เพลง", "ซาวด์"].contains(where: lower.contains) {
            q.kinds.insert(.audio)
        }
        if ["image", "photo", "still", "รูปภาพ", "ภาพนิ่ง", "ภาพถ่าย"].contains(where: lower.contains) {
            q.kinds.insert(.image)
        }

        q.favoritesOnly = ["favorite", "favourite", "โปรด", "ที่ชอบ"].contains(where: lower.contains)
        q.verticalOnly = lower.contains("vertical") || lower.contains("แนวตั้ง")
        q.horizontalOnly = ["horizontal", "landscape", "แนวนอน"].contains(where: lower.contains)

        // Duration bounds: "under/less than 30 seconds", "ไม่เกิน 30 วินาที".
        if let bound = Self.durationBound(in: words) {
            if bound.isUpper { q.maxDuration = bound.seconds } else { q.minDuration = bound.seconds }
        }

        // Free-text terms: drop recognized keywords and units; Thai tokens
        // (often one glued run) shed command/keyword substrings first.
        let reserved: Set<String> = [
            "video", "clip", "footage", "clips", "audio", "music", "sound", "image",
            "photo", "still", "favorite", "favourite", "vertical", "horizontal",
            "landscape", "under", "over", "less", "than", "more", "seconds", "second",
            "minutes", "minute", "sec", "min", "and", "the", "a", "of",
            "วินาที", "นาที", "ไม่เกิน", "เกิน",
        ]
        q.freeTextTerms = words.compactMap { word in
            guard !reserved.contains(word), Int(word) == nil else { return nil }
            guard word.unicodeScalars.contains(where: Self.isThaiScalar) else { return word }
            let cleaned = Self.strippingThaiKeywords(word)
            return cleaned.isEmpty ? nil : cleaned
        }

        self = q
    }

    /// True when the asset satisfies every constraint. Free-text terms match
    /// if *any* term appears in the name or tags (OR), while all other
    /// constraints are ANDed.
    public func matches(_ asset: Asset) -> Bool {
        if !kinds.isEmpty && !kinds.contains(asset.kind) { return false }
        if favoritesOnly && !asset.favorite { return false }
        if !requiredTags.isSubset(of: Set(asset.tags.map { $0.lowercased() })) { return false }

        if verticalOnly, !(asset.format?.isVertical ?? false) { return false }
        if horizontalOnly, asset.format?.isVertical ?? true { return false }

        if let maxDuration, asset.duration.seconds > maxDuration { return false }
        if let minDuration, asset.duration.seconds < minDuration { return false }

        if !freeTextTerms.isEmpty {
            let haystack = ([asset.name.lowercased()] + asset.tags.map { $0.lowercased() })
            let anyMatch = freeTextTerms.contains { Self.termMatches($0, in: haystack) }
            if !anyMatch { return false }
        }
        return true
    }

    /// A relevance score in 0…1 for ranking (more matched terms + favorite
    /// bias). Term relevance is scaled into [0, 0.85] so the favorite bonus
    /// (+0.15) always breaks a tie between otherwise equally-relevant assets.
    public func score(_ asset: Asset) -> Double {
        guard matches(asset) else { return 0 }
        let haystack = ([asset.name.lowercased()] + asset.tags.map { $0.lowercased() })
        let hits = freeTextTerms.filter { Self.termMatches($0, in: haystack) }.count
        let relevance = freeTextTerms.isEmpty ? 0.5 : Double(hits) / Double(freeTextTerms.count)
        return relevance * 0.85 + (asset.favorite ? 0.15 : 0)
    }

    private static func durationBound(in words: [String]) -> (seconds: Double, isUpper: Bool)? {
        // Thai bound words arrive glued to neighbours ("คลิปไม่เกิน"), so
        // Thai checks are substring checks; "ไม่เกิน" (upper) must win over
        // its own suffix "เกิน" (lower).
        let isUpper = words.contains("under") || words.contains("less")
            || words.contains { $0.contains("ไม่เกิน") || $0.contains("สั้นกว่า") }
        let isLower = !isUpper && (words.contains("over") || words.contains("more")
            || words.contains { $0.contains("เกิน") || $0.contains("ยาวกว่า") || $0.contains("มากกว่า") })
        guard isUpper || isLower else { return nil }
        // Find a number followed (soon) by a unit.
        for (index, word) in words.enumerated() {
            guard let value = Double(word) else { continue }
            let unit = words[(index + 1)...].first ?? "seconds"
            let isMinutes = unit.hasPrefix("min")
                || (unit.contains("นาที") && !unit.contains("วินาที"))
            return (isMinutes ? value * 60 : value, isUpper)
        }
        return nil
    }

    // MARK: Thai search support (Workflow Constitution v5: Thai-first)

    /// True when a term matches anything in the haystack, expanding Thai ↔
    /// English synonyms and allowing bidirectional containment for Thai
    /// (Thai queries glue words together: "แมวกลางคืน" must match a "แมว"
    /// or "night" tag).
    static func termMatches(_ term: String, in haystack: [String]) -> Bool {
        for candidate in expansions(of: term) {
            for item in haystack {
                if item.contains(candidate) { return true }
                if (candidate.unicodeScalars.contains(where: isThaiScalar)
                        || item.unicodeScalars.contains(where: isThaiScalar)),
                   item.count >= 2, candidate.contains(item) {
                    return true
                }
            }
        }
        return false
    }

    /// The term itself plus every synonym whose key appears inside it —
    /// glued Thai queries expand every embedded concept.
    static func expansions(of term: String) -> [String] {
        var out = [term]
        for (thai, english) in thaiSynonyms where term.contains(thai) {
            out.append(contentsOf: english)
            out.append(thai)
        }
        for (thai, english) in thaiSynonyms where english.contains(where: term.contains) {
            out.append(thai)
        }
        return out
    }

    /// Curated Thai → English concept synonyms for cross-language search
    /// (assets are often auto-tagged in English while the editor searches in
    /// Thai). Extend freely; both directions are applied.
    static let thaiSynonyms: [String: [String]] = [
        "แมว": ["cat"], "หมา": ["dog"], "สุนัข": ["dog"],
        "รถยนต์": ["car"], "รถ": ["car"],
        "ทะเล": ["sea", "beach", "ocean"], "ชายหาด": ["beach"],
        "ภูเขา": ["mountain"], "ป่า": ["forest"], "เมือง": ["city"],
        "กลางคืน": ["night"], "กลางวัน": ["day", "daytime"],
        "พระอาทิตย์ตก": ["sunset"], "พระอาทิตย์ขึ้น": ["sunrise"],
        "ท้องฟ้า": ["sky"], "ฝน": ["rain"], "หิมะ": ["snow"],
        "อาหาร": ["food"], "กาแฟ": ["coffee"],
        "คน": ["people", "person"], "ยิ้ม": ["smile", "smiling"],
        "เด็ก": ["child", "kid"], "ครอบครัว": ["family"],
        "ดอกไม้": ["flower"], "ต้นไม้": ["tree"], "น้ำตก": ["waterfall"],
        "โดรน": ["drone", "aerial"], "สัมภาษณ์": ["interview"],
        "ท่องเที่ยว": ["travel"], "ธรรมชาติ": ["nature"],
        "สำนักงาน": ["office"], "บ้าน": ["house", "home"],
    ]

    static func isThaiScalar(_ scalar: Unicode.Scalar) -> Bool {
        (0x0E00...0x0E7F).contains(scalar.value)
    }

    /// Removes command words and recognized keywords from a glued Thai token
    /// so only the searchable content remains ("หาคลิปแมวตอนกลางคืนให้หน่อย"
    /// → "แมวกลางคืน").
    static func strippingThaiKeywords(_ token: String) -> String {
        var cleaned = token
        // Longest-first so compounds strip before their parts.
        let substrings = ["ให้หน่อย", "ค้นหา", "รายการโปรด", "ที่ชอบ", "โปรด",
                          "หน่อย", "วิดีโอ", "ฟุตเทจ", "คลิป", "ภาพนิ่ง",
                          "ภาพถ่าย", "รูปภาพ", "แนวตั้ง", "แนวนอน", "ไม่เกิน",
                          "ยาวกว่า", "สั้นกว่า", "มากกว่า", "วินาที",
                          "เสียง", "เพลง", "ซาวด์", "ตอน", "ด้วย"]
        for keyword in substrings {
            cleaned = cleaned.replacingOccurrences(of: keyword, with: "")
        }
        for prefix in ["หา", "ขอ", "เอา"] where cleaned.hasPrefix(prefix) {
            cleaned = String(cleaned.dropFirst(prefix.count))
        }
        return cleaned
    }
}
