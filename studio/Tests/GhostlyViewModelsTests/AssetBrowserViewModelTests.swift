import XCTest
import GhostlyCore
import GhostlyDomain
@testable import GhostlyViewModels

/// The asset browser's data (M2): Thai queries over the library become
/// ranked, Thai-labeled rows — verified without any UI framework.
final class AssetBrowserViewModelTests: XCTestCase {
    private func asset(_ name: String, kind: Asset.Kind = .video,
                       seconds: Double = 75, tags: Set<String> = [],
                       favorite: Bool = false) -> Asset {
        Asset(name: name, url: URL(fileURLWithPath: "/media/\(name)"),
              duration: RationalTime(seconds: seconds), kind: kind,
              format: kind == .video ? .hd1080p30 : nil,
              tags: tags, favorite: favorite)
    }

    private var library: [Asset] {
        [
            asset("cat-day", tags: ["cat", "day"]),
            asset("cat-night", tags: ["cat", "night"], favorite: true),
            asset("dog-park", tags: ["dog"]),
            asset("เพลงประกอบ", kind: .audio, seconds: 130),
            asset("โปสเตอร์", kind: .image, seconds: 0),
        ]
    }

    func testThaiQueryRanksAndFilters() {
        let vm = AssetBrowserViewModel(assets: library, query: "หาคลิปแมว")
        XCTAssertEqual(vm.rows.map(\.name).sorted(), ["cat-day", "cat-night"])
        XCTAssertEqual(vm.rows.first?.name, "cat-night",
                       "favorite bonus must rank the favorite first on a tie")
        XCTAssertEqual(vm.summary, "พบ 2 รายการ")
    }

    func testThaiLabelsAndDurations() {
        let vm = AssetBrowserViewModel(assets: library, query: "")
        let byName = Dictionary(uniqueKeysWithValues: vm.rows.map { ($0.name, $0) })
        XCTAssertEqual(byName["cat-day"]?.kindLabel, "วิดีโอ")
        XCTAssertEqual(byName["cat-day"]?.durationLabel, "1:15")
        XCTAssertEqual(byName["เพลงประกอบ"]?.kindLabel, "เสียง")
        XCTAssertEqual(byName["เพลงประกอบ"]?.durationLabel, "2:10")
        XCTAssertEqual(byName["โปสเตอร์"]?.kindLabel, "รูปภาพ")
        XCTAssertEqual(byName["โปสเตอร์"]?.durationLabel, "-")
    }

    func testEmptyQueryShowsAllFavoritesFirst() {
        let vm = AssetBrowserViewModel(assets: library, query: "  ")
        XCTAssertEqual(vm.rows.count, 5)
        XCTAssertEqual(vm.rows.first?.name, "cat-night")
        XCTAssertTrue(vm.rows.first?.isFavorite ?? false)
    }

    func testNoMatchesSummary() {
        let vm = AssetBrowserViewModel(assets: library, query: "พระอาทิตย์ตก")
        XCTAssertTrue(vm.rows.isEmpty)
        XCTAssertEqual(vm.summary, "ไม่พบรายการที่ตรงกับคำค้น")
    }
}
