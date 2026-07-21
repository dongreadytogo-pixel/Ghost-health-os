import XCTest
import GhostlyCore
import GhostlyDomain
@testable import GhostlyViewModels

/// The timeline inspector's data (M2): pure geometry from a Timeline,
/// verifiable on CI without any UI framework.
final class TimelineViewModelTests: XCTestCase {
    private func fixtureTimeline() -> Timeline {
        let assetID = AssetID("a")
        var timeline = Timeline(name: "ตัวอย่าง", format: .vertical1080x1920p30)
        timeline.appendToStoryline(assetID: assetID, name: "ช็อต 1",
            sourceRange: TimeRange(start: .zero, duration: RationalTime(seconds: 4)))
        timeline.appendToStoryline(assetID: assetID, name: "ช็อต 2",
            sourceRange: TimeRange(start: RationalTime(seconds: 10),
                                   duration: RationalTime(seconds: 6)))
        timeline.clips.append(Clip(
            assetID: assetID, name: "เพลง", offset: .zero,
            sourceRange: TimeRange(start: .zero, duration: RationalTime(seconds: 10)),
            lane: -1, role: .music, volume: 0.35,
            volumeKeyframes: [VolumeKeyframe(time: .zero, gain: 0.35)]))
        timeline.captions = [
            Caption(text: "สวัสดีครับ",
                    range: TimeRange(start: RationalTime(seconds: 1),
                                     duration: RationalTime(seconds: 2)),
                    speaker: "S1", language: "th"),
        ]
        timeline.markers = [Marker(start: RationalTime(seconds: 5), text: "จุดสำคัญ")]
        return timeline
    }

    func testGeometryIsNormalizedAndOrdered() {
        let vm = TimelineViewModel(timeline: fixtureTimeline())
        XCTAssertEqual(vm.durationSeconds, 10, accuracy: 1e-9)
        XCTAssertTrue(vm.isVertical)
        XCTAssertEqual(vm.name, "ตัวอย่าง")

        // Lanes sorted top-down: storyline (0) above music (-1).
        XCTAssertEqual(vm.lanes.map(\.index), [0, -1])
        let story = vm.lanes[0].blocks
        XCTAssertEqual(story.map(\.name), ["ช็อต 1", "ช็อต 2"])
        XCTAssertEqual(story[0].x, 0, accuracy: 1e-9)
        XCTAssertEqual(story[0].width, 0.4, accuracy: 1e-9)
        XCTAssertEqual(story[1].x, 0.4, accuracy: 1e-9)
        XCTAssertEqual(story[1].width, 0.6, accuracy: 1e-9)

        let music = vm.lanes[1].blocks[0]
        XCTAssertEqual(music.roleName, "music")
        XCTAssertTrue(music.hasVolumeAutomation)

        for lane in vm.lanes {
            for block in lane.blocks {
                XCTAssertGreaterThanOrEqual(block.x, 0)
                XCTAssertLessThanOrEqual(block.x + block.width, 1 + 1e-9)
            }
        }
    }

    func testCaptionsMarkersAndTicks() {
        let vm = TimelineViewModel(timeline: fixtureTimeline())
        XCTAssertEqual(vm.captions.count, 1)
        XCTAssertEqual(vm.captions[0].text, "สวัสดีครับ")
        XCTAssertEqual(vm.captions[0].speaker, "S1")
        XCTAssertEqual(vm.captions[0].language, "th")
        XCTAssertEqual(vm.captions[0].x, 0.1, accuracy: 1e-9)

        XCTAssertEqual(vm.markers, [.init(x: 0.5, text: "จุดสำคัญ")])

        // 10 s → 2 s interval → 0,2,4,6,8,10.
        XCTAssertEqual(vm.ticks.map(\.label),
                       ["0:00", "0:02", "0:04", "0:06", "0:08", "0:10"])
        XCTAssertEqual(vm.ticks.first?.x, 0)
        XCTAssertEqual(vm.ticks.last?.x ?? 0, 1, accuracy: 1e-9)
    }

    func testRulerScalesWithDuration() {
        // 90 s → 15 s ticks (7 labels), m:ss formatting past a minute.
        let ticks = TimelineViewModel.rulerTicks(durationSeconds: 90)
        XCTAssertEqual(ticks.count, 7)
        XCTAssertEqual(ticks.last?.label, "1:30")
        // Long form: an hour picks the coarsest interval, still ≤ ~10 ticks.
        XCTAssertLessThanOrEqual(TimelineViewModel.rulerTicks(durationSeconds: 3600).count, 11)
    }

    func testEmptyTimelineIsSafe() {
        let vm = TimelineViewModel(timeline: Timeline(name: "ว่าง", format: .hd1080p30))
        XCTAssertTrue(vm.lanes.isEmpty)
        XCTAssertEqual(vm.ticks, [.init(x: 0, label: "0:00")])
        XCTAssertEqual(vm.durationSeconds, 0)
    }
}
