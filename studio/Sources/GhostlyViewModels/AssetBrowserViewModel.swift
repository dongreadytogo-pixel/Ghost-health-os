import Foundation
import GhostlyCore
import GhostlyDomain
import GhostlyAssets

/// Pure presentation model for the asset browser (M2): a natural-language
/// query — Thai or English — over the asset library becomes ranked, ready-
/// to-draw rows with Thai-first labels. All search semantics live in
/// `AssetQuery` (CI-tested, including the Thai synonym map); this model
/// only ranks and formats.
public struct AssetBrowserViewModel: Sendable, Equatable {
    public struct Row: Sendable, Equatable, Identifiable {
        public let id: AssetID
        public let name: String
        /// Thai media-kind label: วิดีโอ / เสียง / รูปภาพ.
        public let kindLabel: String
        /// "m:ss" duration ("-" for images).
        public let durationLabel: String
        public let tags: [String]
        public let isFavorite: Bool
        public let isVertical: Bool
    }

    public let query: String
    public let rows: [Row]
    /// Thai result summary: "พบ 3 รายการ" (or "ไม่พบรายการที่ตรงกับคำค้น").
    public let summary: String

    public init(assets: [Asset], query: String) {
        self.query = query
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        let ranked: [Asset]
        if trimmed.isEmpty {
            ranked = assets.sorted {
                ($0.favorite ? 0 : 1, $0.name) < ($1.favorite ? 0 : 1, $1.name)
            }
        } else {
            let parsed = AssetQuery(parsing: trimmed)
            ranked = assets
                .map { (asset: $0, score: parsed.score($0)) }
                .filter { $0.score > 0 }
                .sorted { ($0.score, $1.asset.name) > ($1.score, $0.asset.name) }
                .map(\.asset)
        }
        rows = ranked.map(Row.init(asset:))
        summary = rows.isEmpty
            ? "ไม่พบรายการที่ตรงกับคำค้น"
            : "พบ \(rows.count) รายการ"
    }
}

extension AssetBrowserViewModel.Row {
    init(asset: Asset) {
        id = asset.id
        name = asset.name
        switch asset.kind {
        case .video: kindLabel = "วิดีโอ"
        case .audio: kindLabel = "เสียง"
        case .image: kindLabel = "รูปภาพ"
        case .title: kindLabel = "ไตเติล"
        case .generator: kindLabel = "เจเนอเรเตอร์"
        }
        if asset.kind == .image {
            durationLabel = "-"
        } else {
            let seconds = Int(asset.duration.seconds.rounded())
            durationLabel = String(format: "%d:%02d", seconds / 60, seconds % 60)
        }
        tags = asset.tags.sorted()
        isFavorite = asset.favorite
        isVertical = asset.format?.isVertical ?? false
    }
}
