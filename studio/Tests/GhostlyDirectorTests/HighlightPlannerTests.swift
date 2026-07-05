import XCTest
import GhostlyCore
import GhostlyDomain
import GhostlyDetection
import GhostlySubtitles
@testable import GhostlyDirector

final class HighlightPlannerTests: XCTestCase {
    private let asset = AssetID("a")

    private func analysis(duration: Double, speech: [(Double, Double)] = [],
                          cuts: [Double] = [], beats: [Double] = []) -> MediaAnalysis {
        MediaAnalysis(
            assetID: asset,
            duration: RationalTime(seconds: duration, preferredTimescale: 48_000),
            speechRanges: speech.map {
                TimeRange(start: RationalTime(seconds: $0.0, preferredTimescale: 48_000),
                          end: RationalTime(seconds: $0.1, preferredTimescale: 48_000))
            },
            sceneCuts: cuts.map { RationalTime(seconds: $0, preferredTimescale: 48_000) },
            beats: beats.map { RationalTime(seconds: $0, preferredTimescale: 48_000) })
    }

    // MARK: Highlights

    func testHighlightsRankSpeechDenseRegions() {
        // Speech only in 10–20s of a 40s clip → that region should score highest.
        let a = analysis(duration: 40, speech: [(10, 20)])
        let highlights = HighlightPlanner().highlights(from: a, limit: 3)
        XCTAssertFalse(highlights.isEmpty)
        let nonCTA = highlights.filter { $0.kind != .cta }
        XCTAssertFalse(nonCTA.isEmpty)
        let best = nonCTA.max { $0.score < $1.score }!
        XCTAssertTrue(best.range.overlaps(
            TimeRange(start: RationalTime(seconds: 10), end: RationalTime(seconds: 20))))
    }

    func testHookPromotedInFirstThird() {
        let a = analysis(duration: 30, speech: [(0, 6)], beats: Array(stride(from: 0.0, to: 6, by: 0.4)))
        let highlights = HighlightPlanner().highlights(from: a)
        XCTAssertTrue(highlights.contains { $0.kind == .hook })
        let hook = highlights.first { $0.kind == .hook }!
        XCTAssertLessThanOrEqual(hook.range.start.seconds, 10)
        XCTAssertTrue(hook.label.hasPrefix("Hook:"))
    }

    func testCTAAlwaysAppendedNearEnd() {
        let a = analysis(duration: 30, speech: [(0, 30)])
        let highlights = HighlightPlanner(windowDuration: 5).highlights(from: a)
        let cta = highlights.first { $0.kind == .cta }
        XCTAssertNotNil(cta)
        XCTAssertEqual(cta!.range.end.seconds, 30, accuracy: 0.01)
    }

    func testHighlightsRespectSpacing() {
        let a = analysis(duration: 60, speech: [(0, 60)],
                         beats: Array(stride(from: 0.0, to: 60, by: 0.3)))
        let highlights = HighlightPlanner(minimumSpacing: 15)
            .highlights(from: a, limit: 5).filter { $0.kind != .cta }
        let starts = highlights.map(\.range.start.seconds).sorted()
        for (a, b) in zip(starts, starts.dropFirst()) {
            XCTAssertGreaterThanOrEqual(b - a, 15 - 0.01)
        }
    }

    func testEmptyAnalysisYieldsNoHighlights() {
        XCTAssertTrue(HighlightPlanner().highlights(from: analysis(duration: 0)).isEmpty)
    }

    func testTranscriptProvidesLabels() {
        let a = analysis(duration: 20, speech: [(0, 20)])
        let transcript = SubtitleTrack(cues: [
            SubtitleCue(range: TimeRange(start: .zero, duration: RationalTime(seconds: 5)),
                        text: "welcome to the ultimate guide today"),
        ])
        let highlights = HighlightPlanner().highlights(from: a, transcript: transcript)
        XCTAssertTrue(highlights.contains { $0.label.contains("welcome") })
    }

    // MARK: Chapters

    func testChaptersFromSceneCuts() {
        let a = analysis(duration: 60, cuts: [15, 35, 50])
        let chapters = HighlightPlanner(minimumChapterDuration: 10).chapters(from: a)
        XCTAssertEqual(chapters.map(\.start.seconds), [0, 15, 35, 50])
        XCTAssertTrue(chapters.allSatisfy { $0.kind == .chapter })
    }

    func testChaptersEnforceMinimumDuration() {
        // Cuts at 2s and 5s are too close; only spaced ones survive.
        let a = analysis(duration: 60, cuts: [2, 5, 30])
        let chapters = HighlightPlanner(minimumChapterDuration: 10).chapters(from: a)
        XCTAssertEqual(chapters.map(\.start.seconds), [0, 30])
    }

    func testChaptersFallBackToEvenSplitWithoutCuts() {
        let a = analysis(duration: 120)
        let chapters = HighlightPlanner(minimumChapterDuration: 10).chapters(from: a)
        XCTAssertGreaterThan(chapters.count, 1, "long clip with no cuts should still be chaptered")
        XCTAssertEqual(chapters.first?.start.seconds, 0)
    }

    func testChaptersUseTranscriptTitles() {
        let a = analysis(duration: 60, cuts: [20])
        let transcript = SubtitleTrack(cues: [
            SubtitleCue(range: TimeRange(start: RationalTime(seconds: 20),
                                         duration: RationalTime(seconds: 4)),
                        text: "chapter two begins here now"),
        ])
        let chapters = HighlightPlanner().chapters(from: a, transcript: transcript)
        XCTAssertTrue(chapters.contains { $0.text.contains("chapter two") })
    }

    // MARK: Annotation

    func testAnnotateAddsChapterAndHighlightMarkers() {
        let a = analysis(duration: 40, speech: [(5, 35)], cuts: [15, 30])
        let timeline = Timeline(name: "T", format: .hd1080p30)
        let annotated = HighlightPlanner().annotate(timeline, analysis: a)
        XCTAssertGreaterThan(annotated.markers.count, timeline.markers.count)
        XCTAssertTrue(annotated.markers.contains { $0.kind == .chapter })
    }

    func testVisualEngagementPromotesFacingSubject() {
        // Uniform speech across 40s so the base score is flat everywhere; a
        // smile+eye-contact window at 20–26s must win the ranking.
        let a = analysis(duration: 40, speech: [(0, 40)])
        let visual = VisualDetectionAggregator.Summary(
            facePresenceRanges: [TimeRange(start: RationalTime(seconds: 0),
                                           end: RationalTime(seconds: 40))],
            smileRanges: [TimeRange(start: RationalTime(seconds: 20),
                                    end: RationalTime(seconds: 26))],
            eyeContactRanges: [TimeRange(start: RationalTime(seconds: 20),
                                         end: RationalTime(seconds: 26))],
            objectPrevalence: [],
            textRanges: [],
            recognizedText: [])
        let withVisual = HighlightPlanner().highlights(from: a, visual: visual)
        let best = withVisual.filter { $0.kind != .cta }.max { $0.score < $1.score }!
        XCTAssertTrue(best.range.overlaps(
            TimeRange(start: RationalTime(seconds: 20), end: RationalTime(seconds: 26))),
            "the smiling, camera-facing window should rank highest")
    }

    func testVisualNilLeavesRankingUnchanged() {
        let a = analysis(duration: 30, speech: [(0, 30)], cuts: [12],
                         beats: Array(stride(from: 0.0, to: 30, by: 0.5)))
        let withoutArg = HighlightPlanner().highlights(from: a)
        let withNil = HighlightPlanner().highlights(from: a, visual: nil)
        XCTAssertEqual(withoutArg, withNil, "visual is purely additive; nil is a no-op")
    }

    func testDeterminism() {
        let a = analysis(duration: 50, speech: [(0, 50)],
                         cuts: [12, 30], beats: Array(stride(from: 0.0, to: 50, by: 0.5)))
        let first = HighlightPlanner().highlights(from: a)
        let second = HighlightPlanner().highlights(from: a)
        XCTAssertEqual(first, second)
    }
}
