import XCTest
import GhostlyCore
import GhostlyDomain
@testable import GhostlyAssets

/// Thai-first asset search (Workflow Constitution v5): the editor searches
/// in Thai while assets are frequently auto-tagged in English.
final class ThaiSearchTests: XCTestCase {
    private func asset(_ name: String, tags: Set<String>, seconds: Double = 20,
                       kind: Asset.Kind = .video, favorite: Bool = false,
                       vertical: Bool = false) -> Asset {
        Asset(name: name, url: URL(fileURLWithPath: "/media/\(name)"),
              duration: RationalTime(seconds: seconds), kind: kind,
              format: vertical ? .vertical1080x1920p30 : .hd1080p30,
              tags: tags, favorite: favorite)
    }

    func testThaiQueryFindsEnglishTags() {
        let cat = asset("cat-closeup", tags: ["cat", "cute"])
        let dog = asset("dog-park", tags: ["dog"])
        let query = AssetQuery(parsing: "แมว")
        XCTAssertTrue(query.matches(cat), "แมว must find English 'cat' tag")
        XCTAssertFalse(query.matches(dog))
    }

    func testThaiQueryFindsThaiNamesDirectly() {
        let clip = asset("แมวส้มบนหลังคา", tags: [])
        XCTAssertTrue(AssetQuery(parsing: "แมว").matches(clip))
    }

    func testGluedConversationalThaiQuery() {
        // Whole sentence, no spaces, polite particles included.
        let night = asset("b-roll-01", tags: ["cat", "night"])
        let day = asset("b-roll-02", tags: ["dog", "day"])
        let query = AssetQuery(parsing: "หาคลิปแมวตอนกลางคืนให้หน่อย")
        XCTAssertEqual(query.kinds, [.video])
        XCTAssertTrue(query.matches(night))
        XCTAssertFalse(query.matches(day))
    }

    func testThaiKindOrientationAndFavorites() {
        let query = AssetQuery(parsing: "คลิปทะเลแนวตั้ง")
        XCTAssertEqual(query.kinds, [.video])
        XCTAssertTrue(query.verticalOnly)
        let sea = asset("beach-day", tags: ["beach"], vertical: true)
        let seaLandscape = asset("beach-wide", tags: ["beach"])
        XCTAssertTrue(query.matches(sea))
        XCTAssertFalse(query.matches(seaLandscape))

        let favorites = AssetQuery(parsing: "รูปภาพรายการโปรด")
        XCTAssertEqual(favorites.kinds, [.image])
        XCTAssertTrue(favorites.favoritesOnly)
        XCTAssertTrue(favorites.freeTextTerms.isEmpty,
                      "keyword-only query must not demand text matches: \(favorites.freeTextTerms)")
    }

    func testThaiDurationBounds() {
        let short = AssetQuery(parsing: "คลิปไม่เกิน 30 วินาที")
        XCTAssertEqual(short.maxDuration, 30)
        XCTAssertNil(short.minDuration)

        let long = AssetQuery(parsing: "คลิปยาวกว่า 2 นาที")
        XCTAssertEqual(long.minDuration, 120)
        XCTAssertNil(long.maxDuration)
    }

    func testThaiSunsetAndSmileConcepts() {
        let sunset = asset("golden-hour", tags: ["sunset", "sky"])
        XCTAssertTrue(AssetQuery(parsing: "พระอาทิตย์ตก").matches(sunset))
        let smiling = asset("interview-take3", tags: ["people", "smiling"])
        XCTAssertTrue(AssetQuery(parsing: "คนกำลังยิ้ม").matches(smiling))
    }

    func testEnglishQueriesUnchanged() {
        let drone = asset("drone-shot", tags: ["drone", "aerial"], seconds: 25)
        let query = AssetQuery(parsing: "vertical 4k drone clips under 30 seconds")
        XCTAssertEqual(query.maxDuration, 30)
        XCTAssertTrue(query.kinds.contains(.video))
        XCTAssertTrue(query.freeTextTerms.contains("drone"))
        _ = drone
    }

    func testThaiRankingPrefersMoreConcepts() {
        let both = asset("night-cat", tags: ["cat", "night"])
        let one = asset("day-cat", tags: ["cat"])
        let query = AssetQuery(parsing: "แมว กลางคืน")
        XCTAssertGreaterThan(query.score(both), query.score(one))
    }
}
