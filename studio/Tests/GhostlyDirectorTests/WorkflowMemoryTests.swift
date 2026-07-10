import XCTest
import GhostlyCore
import GhostlyDetection
import GhostlyLearning
@testable import GhostlyDirector

/// AI memory (Workflow Constitution v5): the workflow learns the editor's
/// habits and pre-fills them so nothing is configured twice.
final class WorkflowMemoryTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ghostly-memory-tests-\(UUID().uuidString)")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func recording() -> WAV.Audio {
        AudioFixture(sampleRate: 16_000)
            .silence(1.0).speech(2.5).silence(0.5).speech(3.0).silence(1.0)
            .audio()
    }

    func testMemoryPreFillsLearnedExportPreset() async throws {
        let store = try PreferenceStore(directory: directory)
        // The editor exported ProRes twice before.
        try await store.recordUse(of: "ProRes 422 Master", category: .exportPreset)
        try await store.recordUse(of: "ProRes 422 Master", category: .exportPreset)

        let result = try await Workflow.run(Workflow.Request(
            audio: recording(), command: "create a tiktok, remove silence"),
            memory: store)
        XCTAssertEqual(result.exportPresetName, "ProRes 422 Master",
                       "unspecified preset must use the learned favorite, not the inferred one")
    }

    func testExplicitPresetBeatsMemory() async throws {
        let store = try PreferenceStore(directory: directory)
        try await store.recordUse(of: "ProRes 422 Master", category: .exportPreset)
        let result = try await Workflow.run(Workflow.Request(
            audio: recording(), command: "create a tiktok",
            exportPresetName: "TikTok"), memory: store)
        XCTAssertEqual(result.exportPresetName, "TikTok")
    }

    func testWorkflowRecordsWhatItUsed() async throws {
        let store = try PreferenceStore(directory: directory)
        _ = try await Workflow.run(Workflow.Request(
            audio: recording(),
            subtitles: """
            1
            00:00:01,000 --> 00:00:03,000
            สวัสดีครับ
            """,
            command: "ทำเป็นติ๊กต๊อก ตัดช่วงเงียบออก ใส่ซับ"), memory: store)

        let presets = await store.recommendations(for: .exportPreset, limit: 3)
        XCTAssertEqual(presets.first, "TikTok", "used preset must be remembered")
        let pacing = await store.recommendations(for: .pacingStyle, limit: 3)
        XCTAssertEqual(pacing.first, "TikTok")
        let captionStyles = await store.recommendations(for: .captionStyle, limit: 3)
        XCTAssertEqual(captionStyles.first, "TikTok",
                       "Thai command's caption style must be remembered")
    }

    func testForgottenPresetFallsBackToInference() async throws {
        let store = try PreferenceStore(directory: directory)
        // A favorite that no longer exists must not break the workflow.
        try await store.recordUse(of: "Deleted Custom Preset", category: .exportPreset)
        let result = try await Workflow.run(Workflow.Request(
            audio: recording(), command: "create a tiktok"), memory: store)
        XCTAssertEqual(result.exportPresetName, "TikTok",
                       "unknown favorite falls back to format inference")
    }
}
