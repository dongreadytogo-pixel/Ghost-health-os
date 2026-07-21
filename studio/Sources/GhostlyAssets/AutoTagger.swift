import Foundation
import GhostlyCore
import GhostlyDomain

/// Derives descriptive tags for an asset from its intrinsic metadata —
/// kind, format, resolution, aspect ratio, duration, and filename tokens.
/// Deterministic and offline; an AI tagger (Vision/LLM) can layer richer
/// content tags on top through the same `[String]` output.
public struct AutoTagger: Sendable {
    /// Filename tokens shorter than this are ignored as noise.
    public var minimumTokenLength: Int
    /// Common filename tokens that carry no search value.
    private static let stopWords: Set<String> = [
        "the", "and", "final", "copy", "edit", "export", "render", "clip",
        "video", "movie", "footage", "untitled", "new", "test", "temp",
    ]

    public init(minimumTokenLength: Int = 3) {
        self.minimumTokenLength = minimumTokenLength
    }

    /// Tags an asset, merging derived tags with any it already carries.
    public func tags(for asset: Asset) -> Set<String> {
        var tags = asset.tags
        tags.insert(asset.kind.rawValue)

        if let format = asset.format {
            tags.formUnion(resolutionTags(format))
            tags.insert(format.isVertical ? "vertical" : "horizontal")
        }
        tags.formUnion(durationTags(asset.duration, kind: asset.kind))
        tags.formUnion(filenameTokens(asset.name))
        return tags
    }

    /// Returns a copy of the asset with derived tags applied.
    public func tagged(_ asset: Asset) -> Asset {
        var copy = asset
        copy.tags = tags(for: asset)
        return copy
    }

    // MARK: Rules

    private func resolutionTags(_ format: VideoFormat) -> Set<String> {
        let longEdge = max(format.width, format.height)
        var tags: Set<String> = []
        switch longEdge {
        case 7680...: tags.insert("8k")
        case 3840..<7680: tags.insert("4k")
        case 1920..<3840: tags.insert("1080p")
        case 1280..<1920: tags.insert("720p")
        default: tags.insert("sd")
        }
        if format.frameRate.nominalFPS >= 50 { tags.insert("high-fps") }
        return tags
    }

    private func durationTags(_ duration: RationalTime, kind: Asset.Kind) -> Set<String> {
        guard kind == .video || kind == .audio else { return [] }
        switch duration.seconds {
        case ..<0.001: return []
        case ..<15: return ["short-form"]
        case 15..<90: return ["clip-length"]
        case 90..<600: return ["mid-form"]
        default: return ["long-form"]
        }
    }

    private func filenameTokens(_ name: String) -> Set<String> {
        let base = (name as NSString).deletingPathExtension
        let separators = CharacterSet(charactersIn: " _-.()[]#0123456789")
        let tokens = base.lowercased()
            .components(separatedBy: separators)
            .filter { $0.count >= minimumTokenLength && !Self.stopWords.contains($0) }
        return Set(tokens)
    }
}
