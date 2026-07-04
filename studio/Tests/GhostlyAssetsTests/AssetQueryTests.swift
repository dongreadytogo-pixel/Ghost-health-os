import XCTest
import GhostlyCore
import GhostlyDomain
@testable import GhostlyAssets

final class AssetQueryTests: XCTestCase {
    func testParsesKindsAndFlags() {
        let q = AssetQuery(parsing: "favorite vertical drone video")
        XCTAssertTrue(q.kinds.contains(.video))
        XCTAssertTrue(q.favoritesOnly)
        XCTAssertTrue(q.verticalOnly)
        XCTAssertEqual(q.freeTextTerms, ["drone"])
    }

    func testParsesUnderDurationInSeconds() {
        let q = AssetQuery(parsing: "clips under 30 seconds")
        XCTAssertEqual(q.maxDuration, 30)
        XCTAssertNil(q.minDuration)
    }

    func testParsesOverDurationInMinutes() {
        let q = AssetQuery(parsing: "interviews over 2 minutes")
        XCTAssertEqual(q.minDuration, 120)
        XCTAssertNil(q.maxDuration)
        XCTAssertEqual(q.freeTextTerms, ["interviews"])
    }

    func testParsesLandscapeAsHorizontal() {
        XCTAssertTrue(AssetQuery(parsing: "landscape footage").horizontalOnly)
    }

    func testMatchAndScore() {
        let a = Asset(name: "drone_reel", url: URL(string: "file:///d.mov")!,
                      duration: RationalTime(seconds: 10), kind: .video,
                      format: .vertical1080x1920p30, tags: ["drone", "4k"], favorite: true)
        let q = AssetQuery(parsing: "vertical drone under 30 seconds")
        XCTAssertTrue(q.matches(a))
        XCTAssertGreaterThan(q.score(a), 0.5, "matched term + favorite bias")

        let horizontal = AssetQuery(parsing: "horizontal drone")
        XCTAssertFalse(horizontal.matches(a))
    }

    func testDurationBoundExcludes() {
        let long = Asset(name: "x", url: URL(string: "file:///x.mov")!,
                         duration: RationalTime(seconds: 120), kind: .video)
        XCTAssertFalse(AssetQuery(parsing: "under 30 seconds").matches(long))
        XCTAssertTrue(AssetQuery(parsing: "over 1 minutes").matches(long))
    }

    func testRequiredTagsAreCaseInsensitive() {
        let a = Asset(name: "x", url: URL(string: "file:///x.mov")!,
                      duration: RationalTime(seconds: 5), kind: .video, tags: ["Drone"])
        var q = AssetQuery()
        q.requiredTags = ["drone"]
        XCTAssertTrue(q.matches(a))
    }
}
