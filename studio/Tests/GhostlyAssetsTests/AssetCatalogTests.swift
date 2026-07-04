import XCTest
import GhostlyCore
import GhostlyDomain
@testable import GhostlyAssets

final class AssetCatalogTests: XCTestCase {
    private func asset(_ name: String, kind: Asset.Kind = .video, seconds: Double = 30,
                       width: Int? = 1920, height: Int? = 1080, favorite: Bool = false,
                       url: String? = nil) -> Asset {
        let format = (width != nil && height != nil)
            ? VideoFormat(width: width!, height: height!, frameRate: .fps30) : nil
        return Asset(name: name, url: URL(string: url ?? "file:///\(name).mov")!,
                     duration: RationalTime(seconds: seconds, preferredTimescale: 48_000),
                     kind: kind, format: format, favorite: favorite)
    }

    // MARK: Auto-tagging

    func testAutoTaggerDerivesResolutionAspectDurationAndTokens() {
        let a = asset("Sunset_Drone_Flyover", width: 3840, height: 2160, seconds: 8)
        let tags = AutoTagger().tags(for: a)
        XCTAssertTrue(tags.contains("4k"))
        XCTAssertTrue(tags.contains("horizontal"))
        XCTAssertTrue(tags.contains("short-form"))
        XCTAssertTrue(tags.contains("sunset"))
        XCTAssertTrue(tags.contains("drone"))
        XCTAssertTrue(tags.contains("flyover"))
        XCTAssertTrue(tags.contains("video"))
    }

    func testAutoTaggerVerticalAndLongForm() {
        let a = asset("podcast", kind: .audio, seconds: 3600, width: nil, height: nil)
        let tags = AutoTagger().tags(for: a)
        XCTAssertTrue(tags.contains("audio"))
        XCTAssertTrue(tags.contains("long-form"))
        XCTAssertFalse(tags.contains("horizontal"), "audio has no aspect")

        let vertical = asset("reel", width: 1080, height: 1920)
        XCTAssertTrue(AutoTagger().tags(for: vertical).contains("vertical"))
    }

    func testAutoTaggerDropsStopWordsAndShortTokens() {
        let tags = AutoTagger().tags(for: asset("the_final_edit_v2", width: nil, height: nil, seconds: 0))
        XCTAssertFalse(tags.contains("the"))
        XCTAssertFalse(tags.contains("final"))
        XCTAssertFalse(tags.contains("edit"))
    }

    // MARK: Catalog CRUD + collections + folders

    func testAddAppliesTagsAndRemoveCleansUp() throws {
        var catalog = AssetCatalog()
        let stored = catalog.add(asset("drone_shot", width: 3840, height: 2160))
        XCTAssertTrue(stored.tags.contains("4k"))
        XCTAssertEqual(catalog.count, 1)

        try catalog.addToCollection("Aerials", assetID: stored.id)
        try catalog.move(stored.id, toFolder: "B-Roll")
        XCTAssertEqual(catalog.assets(inCollection: "Aerials").count, 1)
        XCTAssertEqual(catalog.assets(inFolder: "B-Roll").count, 1)

        XCTAssertTrue(catalog.remove(stored.id))
        XCTAssertEqual(catalog.count, 0)
        XCTAssertTrue(catalog.assets(inCollection: "Aerials").isEmpty,
                      "removing an asset must drop it from collections")
    }

    func testCollectionOnMissingAssetThrows() {
        var catalog = AssetCatalog()
        XCTAssertThrowsError(try catalog.addToCollection("X", assetID: AssetID("ghost")))
    }

    func testFavorites() {
        var catalog = AssetCatalog()
        let a = catalog.add(asset("a"))
        catalog.add(asset("b", favorite: true))
        XCTAssertEqual(catalog.favorites.count, 1)
        XCTAssertTrue(catalog.setFavorite(a.id, true))
        XCTAssertEqual(catalog.favorites.count, 2)
    }

    func testInsertionOrderPreserved() {
        var catalog = AssetCatalog()
        for name in ["c", "a", "b"] { catalog.add(asset(name)) }
        XCTAssertEqual(catalog.allAssets.map(\.name), ["c", "a", "b"])
    }

    // MARK: Search

    func testNaturalLanguageSearchByKindAspectDuration() {
        var catalog = AssetCatalog()
        catalog.add(asset("drone_reel", width: 1080, height: 1920, seconds: 10))   // vertical, short
        catalog.add(asset("interview", width: 1920, height: 1080, seconds: 600))    // horizontal, long
        catalog.add(asset("bg_music", kind: .audio, seconds: 180, width: nil, height: nil))

        let vertical = catalog.search("vertical clips under 30 seconds")
        XCTAssertEqual(vertical.map(\.name), ["drone_reel"])

        let audio = catalog.search("music")
        XCTAssertEqual(audio.map(\.name), ["bg_music"])
    }

    func testSearchRanksByRelevanceAndFavorite() {
        var catalog = AssetCatalog()
        catalog.add(asset("drone_over_mountains", seconds: 20))
        catalog.add(asset("drone_city", seconds: 20, favorite: true))
        let results = catalog.search("drone")
        XCTAssertEqual(results.count, 2)
        XCTAssertEqual(results.first?.name, "drone_city", "favorite breaks the tie")
    }

    func testSearchFreeTextMatchesTags() {
        var catalog = AssetCatalog()
        catalog.add(asset("clip_001", width: 3840, height: 2160)) // auto-tagged "4k"
        let results = catalog.search("4k")
        XCTAssertEqual(results.count, 1)
    }

    func testEmptyQueryTermsStillFilterByConstraints() {
        var catalog = AssetCatalog()
        catalog.add(asset("v", kind: .video))
        catalog.add(asset("a", kind: .audio, width: nil, height: nil))
        XCTAssertEqual(catalog.search("audio").map(\.name), ["a"])
    }

    // MARK: Housekeeping

    func testDuplicateGroupsByURL() {
        var catalog = AssetCatalog()
        catalog.add(asset("take1", url: "file:///shared.mov"))
        catalog.add(asset("take1_copy", url: "file:///shared.mov"))
        catalog.add(asset("unique", url: "file:///other.mov"))
        let dupes = catalog.duplicateGroups()
        XCTAssertEqual(dupes.count, 1)
        XCTAssertEqual(dupes[0].count, 2)
    }

    func testUnusedAssets() {
        var catalog = AssetCatalog()
        let used = catalog.add(asset("used"))
        catalog.add(asset("unused"))
        var timeline = Timeline(name: "T", format: .hd1080p30)
        timeline.appendToStoryline(assetID: used.id, name: "used",
            sourceRange: TimeRange(start: .zero, duration: RationalTime(seconds: 5)))
        let unused = catalog.unusedAssets(referencedBy: [timeline])
        XCTAssertEqual(unused.map(\.name), ["unused"])
    }

    func testTagFrequencies() {
        var catalog = AssetCatalog()
        catalog.add(asset("a", width: 3840, height: 2160))
        catalog.add(asset("b", width: 3840, height: 2160))
        XCTAssertEqual(catalog.tagFrequencies["4k"], 2)
    }
}
