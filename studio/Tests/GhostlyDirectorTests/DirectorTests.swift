import XCTest
import GhostlyCore
import GhostlyDomain
import GhostlyDetection
import GhostlySubtitles
@testable import GhostlyDirector

final class DirectorTests: XCTestCase {
    // MARK: Intent parsing

    func testParseStyleCommand() {
        let intents = EditIntentParser().parse("Edit this like Marvel.")
        XCTAssertEqual(intents, [.applyStyle(.marvel)])
    }

    func testParseDeliverableCommand() {
        let intents = EditIntentParser().parse("Create TikTok")
        XCTAssertTrue(intents.contains(.applyStyle(.tiktok)) || intents.contains(.createDeliverable(.tiktok)))
    }

    func testParsePacingCommand() {
        XCTAssertEqual(EditIntentParser().parse("Make the pacing faster."),
                       [.adjustPacing(direction: .faster)])
        XCTAssertEqual(EditIntentParser().parse("slow down a bit, let it breathe"),
                       [.adjustPacing(direction: .slower)])
    }

    func testParseMusicCommand() {
        XCTAssertEqual(EditIntentParser().parse("Replace background music."),
                       [.replaceMusic(query: nil)])
        XCTAssertEqual(EditIntentParser().parse("replace the music with epic orchestral rock!"),
                       [.replaceMusic(query: "epic orchestral rock")])
    }

    func testParseCaptionAndSilenceAndBeatCommands() {
        XCTAssertEqual(EditIntentParser().parse("add YouTube captions please"),
                       [.generateCaptions(styleName: "YouTube")])
        XCTAssertEqual(EditIntentParser().parse("remove silence from the vlog"),
                       [.applyStyle(.vlog), .removeSilence])
        XCTAssertTrue(EditIntentParser().parse("cut it to the beat").contains(.cutToBeat))
    }

    func testParseUnknownCommandReturnsEmpty() {
        XCTAssertTrue(EditIntentParser().parse("what's the weather like").isEmpty)
    }

    func testInterpretThrowsOnUnknownCommand() {
        XCTAssertThrowsError(try Director().interpret("hello there"))
    }

    // MARK: Plan resolution

    func testResolveMarvelStyle() throws {
        let plan = try Director().interpret("Edit this like Marvel, cut to the beat")
        XCTAssertEqual(plan.profile.style, .marvel)
        XCTAssertTrue(plan.profile.cutOnBeats)
        XCTAssertLessThanOrEqual(plan.profile.maxShotLength, 3.0)
    }

    func testResolveFasterScalesShotLengths() throws {
        let base = PacingProfile.profile(for: .documentary)
        let plan = try Director().interpret("make the pacing faster", base: base)
        XCTAssertLessThan(plan.profile.maxShotLength, base.maxShotLength)
        XCTAssertEqual(plan.profile.style, .documentary)
    }

    func testResolveTikTokDeliverableIsVerticalWithCaptions() throws {
        let plan = try Director().interpret("create a tiktok from this")
        XCTAssertTrue(plan.profile.format.isVertical)
        XCTAssertTrue(plan.wantsCaptions)
        XCTAssertEqual(plan.profile.captionStyleName, "TikTok")
    }

    func testPacingProfileScaledClampsAndOrders() {
        let p = PacingProfile.profile(for: .tiktok).scaled(by: 0.01)
        XCTAssertGreaterThanOrEqual(p.minShotLength, 0.2)
        XCTAssertGreaterThanOrEqual(p.maxShotLength, p.minShotLength)
    }

    // MARK: Auto-edit planning

    private func fixtureFootage(seconds: Double = 30) -> (Asset, MediaAnalysis) {
        let asset = Asset(name: "talk", url: URL(fileURLWithPath: "/talk.mov"),
                          duration: RationalTime(seconds: seconds, preferredTimescale: 3000),
                          kind: .video, format: .hd1080p30)
        let analysis = MediaAnalysis(
            assetID: asset.id, duration: asset.duration,
            speechRanges: [
                TimeRange(start: RationalTime(seconds: 1), end: RationalTime(seconds: 9)),
                TimeRange(start: RationalTime(seconds: 12), end: RationalTime(seconds: 26)),
            ])
        return (asset, analysis)
    }

    func testPlanRemovesSilenceAndChopsShots() throws {
        let (asset, analysis) = fixtureFootage()
        let profile = PacingProfile.profile(for: .tiktok) // max shot 2.5 s, full silence removal
        let timeline = try AutoEditPlanner(profile: profile)
            .plan(footage: [(asset, analysis)], projectName: "Short")

        XCTAssertFalse(timeline.clips.isEmpty)
        XCTAssertTrue(timeline.validate().isEmpty, "\(timeline.validate())")
        // Total kept ≈ 8 + 14 = 22 s of speech.
        XCTAssertEqual(timeline.duration.seconds, 22, accuracy: 1.0)
        for clip in timeline.storyline {
            XCTAssertLessThanOrEqual(clip.duration.seconds, profile.maxShotLength * 1.5 + 0.05)
        }
        // Source ranges must all be inside speech.
        for clip in timeline.storyline {
            let inSpeech = analysis.speechRanges.contains { speech in
                clip.sourceRange.start >= speech.start && clip.sourceRange.end <= speech.end + RationalTime(value: 1, timescale: 10)
            }
            XCTAssertTrue(inSpeech, "clip source \(clip.sourceRange.start.seconds)s not in speech")
        }
    }

    func testPlanPartialSilenceRemovalKeepsBreathingRoom() throws {
        let (asset, analysis) = fixtureFootage()
        var profile = PacingProfile.profile(for: .podcast)
        profile.silenceRemoval = 0.5
        let timeline = try AutoEditPlanner(profile: profile).plan(footage: [(asset, analysis)])
        // Podcast keeps half of the 3 s pause → ≈ 23.5 s total.
        XCTAssertGreaterThan(timeline.duration.seconds, 22.5)
    }

    func testPlanAddsMusicBedAndBeatMarkers() throws {
        let (asset, analysis) = fixtureFootage()
        let music = Asset(name: "song", url: URL(fileURLWithPath: "/song.wav"),
                          duration: RationalTime(seconds: 60), kind: .audio)
        let beats = stride(from: 0.5, to: 60, by: 0.5).map {
            RationalTime(seconds: $0, preferredTimescale: 1000)
        }
        let musicAnalysis = MediaAnalysis(assetID: music.id, duration: music.duration,
                                          beats: beats, bpm: 120)
        let timeline = try AutoEditPlanner(profile: .profile(for: .tiktok))
            .plan(footage: [(asset, analysis)], music: (music, musicAnalysis))

        let bed = timeline.connectedClips.first { $0.role.name == "music" }
        XCTAssertNotNil(bed)
        XCTAssertEqual(bed?.lane, -1)
        XCTAssertLessThan(bed?.volume ?? 1, 1)
        XCTAssertFalse(timeline.markers.isEmpty)
        XCTAssertTrue(timeline.markers.allSatisfy { $0.start < timeline.duration })
    }

    func testPlanBeatAlignmentKeepsStorylineContiguous() throws {
        let (asset, analysis) = fixtureFootage()
        let music = Asset(name: "song", url: URL(fileURLWithPath: "/song.wav"),
                          duration: RationalTime(seconds: 60), kind: .audio)
        let beats = stride(from: 0.4, to: 60, by: 0.4).map {
            RationalTime(seconds: $0, preferredTimescale: 1000)
        }
        let timeline = try AutoEditPlanner(profile: .profile(for: .marvel))
            .plan(footage: [(asset, analysis)],
                  music: (music, MediaAnalysis(assetID: music.id, duration: music.duration,
                                               beats: beats, bpm: 150)))
        XCTAssertTrue(timeline.validate().isEmpty, "\(timeline.validate())")
    }

    func testPlanAddsCaptionsFromTranscript() throws {
        let (asset, analysis) = fixtureFootage()
        let transcript = SubtitleTrack(cues: [
            SubtitleCue(range: TimeRange(start: RationalTime(seconds: 0),
                                         duration: RationalTime(seconds: 2)),
                        text: "hello and welcome"),
            SubtitleCue(range: TimeRange(start: RationalTime(seconds: 500),
                                         duration: RationalTime(seconds: 2)),
                        text: "past the end"),
        ])
        let timeline = try AutoEditPlanner(profile: .profile(for: .tiktok))
            .plan(footage: [(asset, analysis)], transcript: transcript)
        XCTAssertEqual(timeline.captions.count, 1, "cues beyond the edit must be dropped")
        XCTAssertEqual(timeline.captions[0].text, "HELLO AND WELCOME",
                       "TikTok style upcases captions")
    }

    func testPlanFallsBackToScenesThenWholeAsset() throws {
        let asset = Asset(name: "broll", url: URL(fileURLWithPath: "/b.mov"),
                          duration: RationalTime(seconds: 10), kind: .video, format: .hd1080p30)
        // Scene cuts, no speech.
        let withScenes = MediaAnalysis(assetID: asset.id, duration: asset.duration,
                                       sceneCuts: [RationalTime(seconds: 4)])
        let t1 = try AutoEditPlanner(profile: .profile(for: .vlog))
            .plan(footage: [(asset, withScenes)])
        XCTAssertGreaterThanOrEqual(t1.storyline.count, 2)

        // Nothing detected at all → whole asset.
        let bare = MediaAnalysis(assetID: asset.id, duration: asset.duration)
        let t2 = try AutoEditPlanner(profile: .profile(for: .podcast))
            .plan(footage: [(asset, bare)])
        XCTAssertEqual(t2.duration.seconds, 10, accuracy: 0.1)
    }

    func testPlanRejectsEmptyFootage() {
        XCTAssertThrowsError(try AutoEditPlanner(profile: .profile(for: .vlog)).plan(footage: []))
    }

    func testDocumentaryProfileAddsTransitions() throws {
        let (asset, analysis) = fixtureFootage()
        let timeline = try AutoEditPlanner(profile: .profile(for: .documentary))
            .plan(footage: [(asset, analysis)])
        XCTAssertFalse(timeline.transitions.isEmpty)
        // Transitions sit on cut points, so domain validation still passes.
        XCTAssertTrue(timeline.validate().isEmpty, "\(timeline.validate())")
    }
}
