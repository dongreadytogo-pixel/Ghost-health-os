import XCTest
import GhostlyCore
@testable import GhostlyDomain

final class EditCommandTests: XCTestCase {
    private let asset = AssetID("asset-1")

    private func makeDocument() -> TimelineDocument {
        TimelineDocument(timeline: Timeline(name: "Doc", format: .hd1080p30))
    }

    private func range(_ start: Double, _ duration: Double) -> TimeRange {
        TimeRange(start: RationalTime(seconds: start), duration: RationalTime(seconds: duration))
    }

    // MARK: Individual commands round-trip

    func testAppendClipApplyRevert() throws {
        var timeline = Timeline(name: "T", format: .hd1080p30)
        let original = timeline
        let command = AppendClipCommand(assetID: asset, clipName: "A", sourceRange: range(0, 5))
        try command.apply(to: &timeline)
        XCTAssertEqual(timeline.storyline.count, 1)
        XCTAssertEqual(timeline.storyline[0].offset, .zero)
        try command.revert(from: &timeline)
        XCTAssertEqual(timeline.clips, original.clips)
    }

    func testAppendPlacesAtStorylineEnd() throws {
        var timeline = Timeline(name: "T", format: .hd1080p30)
        try AppendClipCommand(assetID: asset, clipName: "A", sourceRange: range(0, 5)).apply(to: &timeline)
        try AppendClipCommand(assetID: asset, clipName: "B", sourceRange: range(0, 3)).apply(to: &timeline)
        XCTAssertEqual(timeline.storyline.map(\.name), ["A", "B"])
        XCTAssertEqual(timeline.storyline[1].offset.seconds, 5)
    }

    func testRemoveClipRestoresPosition() throws {
        var timeline = Timeline(name: "T", format: .hd1080p30)
        let a = AppendClipCommand(assetID: asset, clipName: "A", sourceRange: range(0, 5))
        let b = AppendClipCommand(assetID: asset, clipName: "B", sourceRange: range(0, 5))
        try a.apply(to: &timeline)
        try b.apply(to: &timeline)
        let snapshot = timeline.clips

        let remove = RemoveClipCommand(clipID: a.clip.id)
        try remove.apply(to: &timeline)
        XCTAssertEqual(timeline.clips.count, 1)
        try remove.revert(from: &timeline)
        XCTAssertEqual(timeline.clips.map(\.id), snapshot.map(\.id),
                       "removed clip must return to its original index")
    }

    func testMoveTrimRenameRoundTrip() throws {
        var timeline = Timeline(name: "T", format: .hd1080p30)
        let append = AppendClipCommand(assetID: asset, clipName: "A", sourceRange: range(0, 5))
        try append.apply(to: &timeline)
        let id = append.clip.id

        let move = MoveClipCommand(clipID: id, to: RationalTime(seconds: 10))
        try move.apply(to: &timeline)
        XCTAssertEqual(timeline.clips[0].offset.seconds, 10)
        try move.revert(from: &timeline)
        XCTAssertEqual(timeline.clips[0].offset.seconds, 0)

        let trim = TrimClipCommand(clipID: id, to: range(1, 2))
        try trim.apply(to: &timeline)
        XCTAssertEqual(timeline.clips[0].sourceRange.duration.seconds, 2)
        try trim.revert(from: &timeline)
        XCTAssertEqual(timeline.clips[0].sourceRange.duration.seconds, 5)

        let rename = RenameClipCommand(clipID: id, to: "Renamed")
        try rename.apply(to: &timeline)
        XCTAssertEqual(timeline.clips[0].name, "Renamed")
        try rename.revert(from: &timeline)
        XCTAssertEqual(timeline.clips[0].name, "A")
    }

    func testTrimRejectsZeroDuration() {
        var timeline = Timeline(name: "T", format: .hd1080p30)
        let append = AppendClipCommand(assetID: asset, clipName: "A", sourceRange: range(0, 5))
        try? append.apply(to: &timeline)
        let trim = TrimClipCommand(clipID: append.clip.id,
                                   to: TimeRange(start: .zero, duration: .zero))
        XCTAssertThrowsError(try trim.apply(to: &timeline))
    }

    func testCommandsThrowOnMissingClip() {
        var timeline = Timeline(name: "T", format: .hd1080p30)
        XCTAssertThrowsError(try MoveClipCommand(clipID: ClipID("nope"), to: .zero).apply(to: &timeline))
        XCTAssertThrowsError(try RemoveClipCommand(clipID: ClipID("nope")).apply(to: &timeline))
    }

    // MARK: Document undo/redo

    func testPerformUndoRedo() throws {
        let doc = makeDocument()
        XCTAssertFalse(doc.canUndo)
        try doc.perform(AppendClipCommand(assetID: asset, clipName: "A", sourceRange: range(0, 5)))
        try doc.perform(AppendClipCommand(assetID: asset, clipName: "B", sourceRange: range(0, 5)))
        XCTAssertEqual(doc.timeline.storyline.count, 2)
        XCTAssertTrue(doc.canUndo)
        XCTAssertFalse(doc.canRedo)

        XCTAssertTrue(try doc.undo())
        XCTAssertEqual(doc.timeline.storyline.count, 1)
        XCTAssertTrue(doc.canRedo)
        XCTAssertTrue(try doc.undo())
        XCTAssertEqual(doc.timeline.storyline.count, 0)
        XCTAssertFalse(doc.canUndo)

        XCTAssertTrue(try doc.redo())
        XCTAssertTrue(try doc.redo())
        XCTAssertEqual(doc.timeline.storyline.count, 2)
        XCTAssertFalse(doc.canRedo)
    }

    func testPerformClearsRedoStack() throws {
        let doc = makeDocument()
        try doc.perform(AppendClipCommand(assetID: asset, clipName: "A", sourceRange: range(0, 5)))
        try doc.undo()
        XCTAssertTrue(doc.canRedo)
        try doc.perform(AppendClipCommand(assetID: asset, clipName: "C", sourceRange: range(0, 5)))
        XCTAssertFalse(doc.canRedo, "a new command must clear the redo stack")
        XCTAssertEqual(doc.timeline.storyline.map(\.name), ["C"])
    }

    func testUndoRedoOnEmptyStacksIsNoOp() throws {
        let doc = makeDocument()
        XCTAssertFalse(try doc.undo())
        XCTAssertFalse(try doc.redo())
    }

    func testFailedCommandLeavesTimelineUnchanged() {
        let doc = makeDocument()
        XCTAssertThrowsError(try doc.perform(RemoveClipCommand(clipID: ClipID("ghost"))))
        XCTAssertEqual(doc.timeline.clips.count, 0)
        XCTAssertFalse(doc.canUndo, "a throwing command must not enter history")
    }

    func testHistoryDepthIsBounded() throws {
        let doc = TimelineDocument(timeline: Timeline(name: "T", format: .hd1080p30),
                                   maxHistoryDepth: 3)
        for i in 0..<10 {
            try doc.perform(AppendClipCommand(assetID: asset, clipName: "C\(i)", sourceRange: range(0, 1)))
        }
        XCTAssertEqual(doc.undoableCommandNames.count, 3)
        XCTAssertEqual(doc.timeline.storyline.count, 10)
    }

    func testResetClearsHistoryAndEmitsEvent() throws {
        let doc = makeDocument()
        try doc.perform(AppendClipCommand(assetID: asset, clipName: "A", sourceRange: range(0, 5)))
        var events: [DomainEvent] = []
        doc.subscribe { events.append($0) }
        doc.reset(to: Timeline(name: "Fresh", format: .hd1080p30))
        XCTAssertFalse(doc.canUndo)
        XCTAssertEqual(doc.timeline.name, "Fresh")
        XCTAssertEqual(events, [.reset])
    }

    func testDomainEventsEmitted() throws {
        let doc = makeDocument()
        var events: [DomainEvent] = []
        doc.subscribe { events.append($0) }
        try doc.perform(AppendClipCommand(assetID: asset, clipName: "A", sourceRange: range(0, 5)))
        try doc.undo()
        try doc.redo()
        XCTAssertEqual(events, [.commandApplied(name: "Append Clip"),
                               .undone(name: "Append Clip"),
                               .redone(name: "Append Clip")])
    }

    func testCaptionAndMarkerCommands() throws {
        let doc = makeDocument()
        let caption = Caption(text: "hi", range: range(0, 2))
        try doc.perform(AddCaptionCommand(caption: caption))
        XCTAssertEqual(doc.timeline.captions.count, 1)
        try doc.perform(AddMarkerCommand(marker: Marker(start: RationalTime(seconds: 1), text: "m")))
        XCTAssertEqual(doc.timeline.markers.count, 1)
        try doc.undo()
        try doc.undo()
        XCTAssertTrue(doc.timeline.captions.isEmpty)
        XCTAssertTrue(doc.timeline.markers.isEmpty)
    }
}
