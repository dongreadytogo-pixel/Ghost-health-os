import XCTest
import GhostlyCore
@testable import GhostlyDomain

final class TimelineTests: XCTestCase {
    private func makeAsset(seconds: Int = 60) -> Asset {
        Asset(name: "interview", url: URL(fileURLWithPath: "/media/interview.mov"),
              duration: RationalTime(seconds: seconds), kind: .video, format: .hd1080p30)
    }

    func testAppendToStorylinePlacesClipsBackToBack() {
        var timeline = Timeline(name: "Cut 1", format: .hd1080p30)
        let asset = makeAsset()
        timeline.appendToStoryline(assetID: asset.id, name: "A",
            sourceRange: TimeRange(start: .zero, duration: RationalTime(seconds: 5)))
        timeline.appendToStoryline(assetID: asset.id, name: "B",
            sourceRange: TimeRange(start: RationalTime(seconds: 10), duration: RationalTime(seconds: 3)))

        let story = timeline.storyline
        XCTAssertEqual(story.map(\.name), ["A", "B"])
        XCTAssertEqual(story[1].offset.seconds, 5)
        XCTAssertEqual(timeline.duration.seconds, 8)
        XCTAssertTrue(timeline.validate().isEmpty)
    }

    func testValidateDetectsOverlapAndGap() {
        var timeline = Timeline(name: "Bad", format: .hd1080p30)
        let asset = makeAsset()
        let five = RationalTime(seconds: 5)
        timeline.clips = [
            Clip(assetID: asset.id, name: "A", offset: .zero,
                 sourceRange: TimeRange(start: .zero, duration: five)),
            Clip(assetID: asset.id, name: "B", offset: RationalTime(seconds: 4),
                 sourceRange: TimeRange(start: .zero, duration: five)),
            Clip(assetID: asset.id, name: "C", offset: RationalTime(seconds: 20),
                 sourceRange: TimeRange(start: .zero, duration: five)),
        ]
        let problems = timeline.validate()
        XCTAssertTrue(problems.contains { $0.contains("overlap") })
        XCTAssertTrue(problems.contains { $0.contains("gap") })
    }

    func testValidateDetectsZeroDurationAndOffCutTransition() {
        var timeline = Timeline(name: "Bad2", format: .hd1080p30)
        let asset = makeAsset()
        timeline.clips = [
            Clip(assetID: asset.id, name: "Z", offset: .zero,
                 sourceRange: TimeRange(start: .zero, duration: .zero)),
        ]
        timeline.transitions = [
            .crossDissolve(offset: RationalTime(seconds: 3), duration: RationalTime(seconds: 1)),
        ]
        let problems = timeline.validate()
        XCTAssertTrue(problems.contains { $0.contains("zero duration") })
        XCTAssertTrue(problems.contains { $0.contains("not on a cut point") })
    }

    func testConnectedClipsAreSeparatedFromStoryline() {
        var timeline = Timeline(name: "Lanes", format: .hd1080p30)
        let asset = makeAsset()
        let r = TimeRange(start: .zero, duration: RationalTime(seconds: 2))
        timeline.clips = [
            Clip(assetID: asset.id, name: "story", offset: .zero, sourceRange: r, lane: 0),
            Clip(assetID: asset.id, name: "broll", offset: .zero, sourceRange: r, lane: 1),
            Clip(assetID: asset.id, name: "music", offset: .zero, sourceRange: r, lane: -1),
        ]
        XCTAssertEqual(timeline.storyline.map(\.name), ["story"])
        XCTAssertEqual(Set(timeline.connectedClips.map(\.name)), ["broll", "music"])
    }

    func testEntityIDsAreTypeDistinctAndCodable() throws {
        let assetID = AssetID("abc")
        let data = try JSONEncoder().encode(assetID)
        XCTAssertEqual(String(data: data, encoding: .utf8), "\"abc\"")
        let decoded = try JSONDecoder().decode(AssetID.self, from: data)
        XCTAssertEqual(decoded, assetID)
    }

    func testRoleDescription() {
        XCTAssertEqual(Role.dialogue.description, "dialogue")
        XCTAssertEqual(Role("music", subrole: "music-1").description, "music.music-1")
    }

    func testTimelineCodableRoundTrip() throws {
        var timeline = Timeline(name: "RT", format: .vertical1080x1920p30)
        let asset = makeAsset()
        timeline.appendToStoryline(assetID: asset.id, name: "A",
            sourceRange: TimeRange(start: .zero, duration: RationalTime(seconds: 5)))
        timeline.captions.append(Caption(text: "hello",
            range: TimeRange(start: .zero, duration: RationalTime(seconds: 2))))
        timeline.markers.append(Marker(start: RationalTime(seconds: 1), text: "beat"))

        let data = try JSONEncoder().encode(timeline)
        let decoded = try JSONDecoder().decode(Timeline.self, from: data)
        XCTAssertEqual(decoded.name, "RT")
        XCTAssertEqual(decoded.clips.count, 1)
        XCTAssertEqual(decoded.captions.first?.text, "hello")
        XCTAssertEqual(decoded.format.isVertical, true)
    }
}
