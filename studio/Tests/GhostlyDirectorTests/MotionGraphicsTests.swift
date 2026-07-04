import XCTest
import GhostlyCore
import GhostlyDomain
@testable import GhostlyDirector

final class MotionGraphicsTests: XCTestCase {
    private let library = MotionGraphicsLibrary()

    func testLowerThirdCombinesNameAndSubtitle() {
        let title = library.lowerThird(name: "Jane Doe", subtitle: "CEO", start: 5)
        XCTAssertEqual(title.kind, .lowerThird)
        XCTAssertEqual(title.text, "Jane Doe\nCEO")
        XCTAssertEqual(title.range.start.seconds, 5)
        XCTAssertEqual(title.range.duration.seconds, 4)
        XCTAssertEqual(title.position, .lowerThird)
    }

    func testLowerThirdWithoutSubtitle() {
        let title = library.lowerThird(name: "Solo", start: 0)
        XCTAssertEqual(title.text, "Solo")
    }

    func testTitleCardAndCalloutAndSubscribe() {
        XCTAssertEqual(library.titleCard("Chapter One", start: 0).kind, .titleCard)
        XCTAssertEqual(library.titleCard("Chapter One", start: 0).position, .center)
        XCTAssertEqual(library.callout("Look here", start: 2, position: .top).kind, .callout)
        XCTAssertEqual(library.subscribeAnimation(start: 50).text, "SUBSCRIBE")
        XCTAssertEqual(library.subscribeAnimation(start: 50).kind, .subscribe)
    }

    func testProgressBarSpansRange() {
        let bar = library.progressBar(start: 10, duration: 30)
        XCTAssertEqual(bar.kind, .progressBar)
        XCTAssertEqual(bar.range.end.seconds, 40)
        XCTAssertTrue(bar.text.isEmpty)
    }

    func testGraphicsUseConfiguredLane() {
        let custom = MotionGraphicsLibrary(lane: 5)
        XCTAssertEqual(custom.titleCard("x", start: 0).lane, 5)
    }

    func testLowerThirdsForSpeakersDedupesConsecutive() {
        let titles = library.lowerThirdsForSpeakers(names: [
            ("Alice", 0), ("Alice", 3), ("Bob", 6), ("Alice", 10),
        ])
        // Alice(0) → Bob(6) → Alice(10): the repeated Alice at 3 is skipped.
        XCTAssertEqual(titles.map(\.text), ["Alice", "Bob", "Alice"])
        XCTAssertEqual(titles.map(\.range.start.seconds), [0, 6, 10])
    }

    func testTitlesAttachToTimelineAndSurviveCodable() throws {
        var timeline = Timeline(name: "T", format: .hd1080p30)
        timeline.titles = [library.titleCard("Intro", start: 0)]
        let data = try JSONEncoder().encode(timeline)
        let decoded = try JSONDecoder().decode(Timeline.self, from: data)
        XCTAssertEqual(decoded.titles.count, 1)
        XCTAssertEqual(decoded.titles[0].text, "Intro")
    }

    func testTimelineWithoutTitlesKeyStillDecodes() throws {
        // Older serialized timelines have no "titles" field.
        let json = """
        {"name":"Old","format":{"width":1920,"height":1080,
        "frameRate":{"frames":30,"secondsPerBatch":1},"colorSpace":"1-1-1 (Rec. 709)"},
        "clips":[],"transitions":[],"captions":[],"markers":[]}
        """
        let decoded = try JSONDecoder().decode(Timeline.self, from: Data(json.utf8))
        XCTAssertTrue(decoded.titles.isEmpty)
    }
}
