import Foundation
import GhostlyCore
import GhostlyDomain

/// An in-memory asset library: storage plus collections, favorites, folders,
/// a tag index, natural-language search, and housekeeping queries
/// (duplicate/unused finders). Pure value type — persistence layers wrap it.
public struct AssetCatalog: Sendable {
    private var assets: [AssetID: Asset]
    private var order: [AssetID]
    /// Named collections → member asset ids.
    private var collections: [String: Set<AssetID>]
    /// Folder path → member asset ids (single-folder membership).
    private var folders: [AssetID: String]
    private let tagger: AutoTagger

    public init(tagger: AutoTagger = AutoTagger()) {
        self.assets = [:]
        self.order = []
        self.collections = [:]
        self.folders = [:]
        self.tagger = tagger
    }

    public var allAssets: [Asset] { order.compactMap { assets[$0] } }
    public var count: Int { assets.count }

    // MARK: Mutation

    /// Adds (or replaces) an asset, applying auto-tagging.
    @discardableResult
    public mutating func add(_ asset: Asset, autoTag: Bool = true) -> Asset {
        let stored = autoTag ? tagger.tagged(asset) : asset
        if assets[stored.id] == nil { order.append(stored.id) }
        assets[stored.id] = stored
        return stored
    }

    public mutating func add(contentsOf newAssets: [Asset], autoTag: Bool = true) {
        for asset in newAssets { add(asset, autoTag: autoTag) }
    }

    @discardableResult
    public mutating func remove(_ id: AssetID) -> Bool {
        guard assets.removeValue(forKey: id) != nil else { return false }
        order.removeAll { $0 == id }
        folders.removeValue(forKey: id)
        for key in collections.keys { collections[key]?.remove(id) }
        return true
    }

    public func asset(_ id: AssetID) -> Asset? { assets[id] }

    @discardableResult
    public mutating func setFavorite(_ id: AssetID, _ favorite: Bool) -> Bool {
        guard var asset = assets[id] else { return false }
        asset.favorite = favorite
        assets[id] = asset
        return true
    }

    // MARK: Collections & folders

    public mutating func addToCollection(_ name: String, assetID: AssetID) throws {
        guard assets[assetID] != nil else {
            throw StudioError.notFound(entity: "Asset", id: assetID.rawValue)
        }
        collections[name, default: []].insert(assetID)
    }

    public mutating func removeFromCollection(_ name: String, assetID: AssetID) {
        collections[name]?.remove(assetID)
        if collections[name]?.isEmpty == true { collections.removeValue(forKey: name) }
    }

    public var collectionNames: [String] { collections.keys.sorted() }

    public func assets(inCollection name: String) -> [Asset] {
        (collections[name] ?? []).compactMap { assets[$0] }
            .sorted { orderIndex($0.id) < orderIndex($1.id) }
    }

    public mutating func move(_ id: AssetID, toFolder folder: String) throws {
        guard assets[id] != nil else {
            throw StudioError.notFound(entity: "Asset", id: id.rawValue)
        }
        folders[id] = folder
    }

    public func assets(inFolder folder: String) -> [Asset] {
        order.filter { folders[$0] == folder }.compactMap { assets[$0] }
    }

    public var favorites: [Asset] { allAssets.filter(\.favorite) }

    // MARK: Search

    /// Natural-language search, ranked by relevance (highest first).
    public func search(_ query: String) -> [Asset] {
        search(AssetQuery(parsing: query))
    }

    public func search(_ query: AssetQuery) -> [Asset] {
        allAssets
            .map { (asset: $0, score: query.score($0)) }
            .filter { $0.score > 0 }
            .sorted {
                $0.score != $1.score ? $0.score > $1.score
                    : orderIndex($0.asset.id) < orderIndex($1.asset.id)
            }
            .map(\.asset)
    }

    /// All tags present across the catalog with their frequencies.
    public var tagFrequencies: [String: Int] {
        var counts: [String: Int] = [:]
        for asset in allAssets {
            for tag in asset.tags { counts[tag, default: 0] += 1 }
        }
        return counts
    }

    // MARK: Housekeeping

    /// Groups assets that point at the same media URL (likely duplicates).
    public func duplicateGroups() -> [[Asset]] {
        Dictionary(grouping: allAssets) { $0.url.absoluteString }
            .values
            .filter { $0.count > 1 }
            .map { $0.sorted { orderIndex($0.id) < orderIndex($1.id) } }
            .sorted { orderIndex($0[0].id) < orderIndex($1[0].id) }
    }

    /// Assets not referenced by any clip in the given timelines.
    public func unusedAssets(referencedBy timelines: [Timeline]) -> [Asset] {
        let used = Set(timelines.flatMap { $0.clips.map(\.assetID) })
        return allAssets.filter { !used.contains($0.id) }
    }

    private func orderIndex(_ id: AssetID) -> Int {
        order.firstIndex(of: id) ?? Int.max
    }
}
