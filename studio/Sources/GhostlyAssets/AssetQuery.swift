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

    /// Parses a free-form query. Recognizes kinds, favorite/vertical/
    /// horizontal keywords, and "under/over N seconds/minutes" duration
    /// bounds; every remaining word becomes a free-text term matched against
    /// the asset's name and tags.
    public init(parsing query: String) {
        var q = AssetQuery()
        let lower = query.lowercased()
        let words = lower.components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }

        // Kinds.
        if lower.contains("video") || lower.contains("clip") || lower.contains("footage") {
            q.kinds.insert(.video)
        }
        if lower.contains("audio") || lower.contains("music") || lower.contains("sound") {
            q.kinds.insert(.audio)
        }
        if lower.contains("image") || lower.contains("photo") || lower.contains("still") {
            q.kinds.insert(.image)
        }

        q.favoritesOnly = lower.contains("favorite") || lower.contains("favourite")
        q.verticalOnly = lower.contains("vertical")
        q.horizontalOnly = lower.contains("horizontal") || lower.contains("landscape")

        // Duration bounds: "under/less than 30 seconds", "over 2 minutes".
        if let bound = Self.durationBound(in: words) {
            if bound.isUpper { q.maxDuration = bound.seconds } else { q.minDuration = bound.seconds }
        }

        // Free-text terms: drop recognized keywords and units.
        let reserved: Set<String> = [
            "video", "clip", "footage", "clips", "audio", "music", "sound", "image",
            "photo", "still", "favorite", "favourite", "vertical", "horizontal",
            "landscape", "under", "over", "less", "than", "more", "seconds", "second",
            "minutes", "minute", "sec", "min", "and", "the", "a", "of",
        ]
        q.freeTextTerms = words.filter { !reserved.contains($0) && Int($0) == nil }

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
            let anyMatch = freeTextTerms.contains { term in
                haystack.contains { $0.contains(term) }
            }
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
        let hits = freeTextTerms.filter { term in haystack.contains { $0.contains(term) } }.count
        let relevance = freeTextTerms.isEmpty ? 0.5 : Double(hits) / Double(freeTextTerms.count)
        return relevance * 0.85 + (asset.favorite ? 0.15 : 0)
    }

    private static func durationBound(in words: [String]) -> (seconds: Double, isUpper: Bool)? {
        let isUpper = words.contains("under") || words.contains("less")
        let isLower = words.contains("over") || words.contains("more")
        guard isUpper || isLower else { return nil }
        // Find a number followed (soon) by a unit.
        for (index, word) in words.enumerated() {
            guard let value = Double(word) else { continue }
            let unit = words[(index + 1)...].first ?? "seconds"
            let seconds = unit.hasPrefix("min") ? value * 60 : value
            return (seconds, isUpper)
        }
        return nil
    }
}
