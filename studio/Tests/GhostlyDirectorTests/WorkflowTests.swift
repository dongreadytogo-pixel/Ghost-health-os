import XCTest
import GhostlyCore
import GhostlyDetection
@testable import GhostlyDirector

final class WorkflowTests: XCTestCase {
    private func recording() -> WAV.Audio {
        AudioFixture(sampleRate: 16_000)
            .silence(1.0).speech(2.5)
            .silence(0.5).speech(3.0)
            .silence(1.0)
            .audio()
    }

    func testAudioWorkflowInfersVerticalPresetAndBuildsExportCommand() throws {
        let result = try Workflow.run(Workflow.Request(
            audio: recording(),
            command: "create a tiktok, remove silence",
            clipName: "คลิป.mov"))
        XCTAssertTrue(result.edit.isValid, "issues: \(result.edit.issues)")
        XCTAssertEqual(result.exportPresetName, "TikTok",
                       "vertical edit must infer the TikTok preset")
        XCTAssertTrue(result.exportCommand.contains("scale=1080:1920"),
                      "export command must render vertical: \(result.exportCommand)")
        XCTAssertTrue(result.exportCommand.hasPrefix("ffmpeg "))
        XCTAssertFalse(result.steps.isEmpty)
        XCTAssertTrue(result.steps.contains { $0.contains("analyzed") })
        XCTAssertTrue(result.steps.contains { $0.contains("TikTok") })
    }

    func testTranscriptWorkflowLandscapeDefaultsToYouTube() throws {
        let srt = """
        1
        00:00:01,000 --> 00:00:04,000
        สวัสดีครับวันนี้มาคุยกันเรื่องกล้อง
        """
        let result = try Workflow.run(Workflow.Request(
            subtitles: srt, durationSeconds: 6,
            command: "add captions"))
        XCTAssertTrue(result.edit.isValid)
        XCTAssertEqual(result.exportPresetName, "YouTube 1080p")
        XCTAssertEqual(result.edit.language, "th", "Thai is the default language")
    }

    func testExplicitPresetHonoredAndUnknownRejected() throws {
        let request = { (preset: String?) in
            Workflow.Request(audio: self.recording(),
                             command: "create a tiktok",
                             exportPresetName: preset)
        }
        let master = try Workflow.run(request("ProRes 422 Master"))
        XCTAssertEqual(master.exportPresetName, "ProRes 422 Master")
        XCTAssertThrowsError(try Workflow.run(request("No Such Preset"))) { error in
            guard case StudioError.notFound = error else {
                return XCTFail("expected notFound, got \(error)")
            }
        }
    }

    func testRequiresSomeInput() {
        XCTAssertThrowsError(try Workflow.run(Workflow.Request(command: "create a tiktok")))
    }

    func testDeterministicTrace() throws {
        let make = { try Workflow.run(Workflow.Request(
            audio: self.recording(), command: "create a tiktok, remove silence")) }
        let a = try make()
        let b = try make()
        XCTAssertEqual(a.steps, b.steps)
        XCTAssertEqual(a.exportCommand, b.exportCommand)
        XCTAssertEqual(a.edit.fcpxml, b.edit.fcpxml)
    }
}
