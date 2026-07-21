import XCTest
import GhostlyCore
@testable import GhostlyLearning

final class LearningTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ghostly-tests-\(UUID().uuidString)")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    func testRecordAndRecommend() async throws {
        let store = try PreferenceStore(directory: directory)
        try await store.recordUse(of: "Cross Dissolve", category: .transition)
        try await store.recordUse(of: "Cross Dissolve", category: .transition)
        try await store.recordUse(of: "Slide", category: .transition)
        let recs = await store.recommendations(for: .transition)
        XCTAssertEqual(recs.first, "Cross Dissolve")
        XCTAssertEqual(recs.count, 2)
    }

    func testRecencyDecayOutweighsStaleCounts() async throws {
        let store = try PreferenceStore(directory: directory)
        let longAgo = Date(timeIntervalSinceNow: -365 * 24 * 3600)
        for _ in 0..<5 {
            try await store.recordUse(of: "Old Favorite", category: .lut, at: longAgo)
        }
        try await store.recordUse(of: "New Look", category: .lut)
        let recs = await store.recommendations(for: .lut)
        XCTAssertEqual(recs.first, "New Look",
                       "5 uses a year ago decay below 1 use today with a 30-day half-life")
    }

    func testPersistenceAcrossInstances() async throws {
        do {
            let store = try PreferenceStore(directory: directory)
            try await store.set(font: "Proxima Nova", captionStyle: "TikTok")
            try await store.recordPrompt("edit this like marvel")
        }
        let reloaded = try PreferenceStore(directory: directory)
        let prefs = await reloaded.current
        XCTAssertEqual(prefs.preferredFont, "Proxima Nova")
        XCTAssertEqual(prefs.preferredCaptionStyle, "TikTok")
        XCTAssertEqual(prefs.recentPrompts, ["edit this like marvel"])
    }

    func testPromptHistoryDedupesAndBounds() async throws {
        let store = try PreferenceStore(directory: directory)
        try await store.recordPrompt("make it faster")
        try await store.recordPrompt("add captions")
        try await store.recordPrompt("make it faster") // moves to end, no dup
        var prompts = await store.current.recentPrompts
        XCTAssertEqual(prompts, ["add captions", "make it faster"])

        for i in 0..<(PreferenceStore.maxRecentPrompts + 10) {
            try await store.recordPrompt("prompt \(i)")
        }
        prompts = await store.current.recentPrompts
        XCTAssertEqual(prompts.count, PreferenceStore.maxRecentPrompts)
        XCTAssertEqual(prompts.last, "prompt \(PreferenceStore.maxRecentPrompts + 9)")
    }

    func testEmptyPromptIgnored() async throws {
        let store = try PreferenceStore(directory: directory)
        try await store.recordPrompt("   \n")
        let prompts = await store.current.recentPrompts
        XCTAssertTrue(prompts.isEmpty)
    }

    func testCorruptFileIsQuarantinedNotFatal() async throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent("preferences.json")
        try Data("{not json]".utf8).write(to: file)

        let store = try PreferenceStore(directory: directory)
        let prefs = await store.current
        XCTAssertEqual(prefs, UserPreferences())
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: directory.appendingPathComponent("preferences.json.corrupt").path),
            "corrupt file must be kept for inspection")
        // Store still works.
        try await store.recordUse(of: "Helvetica", category: .font)
        let recs = await store.recommendations(for: .font)
        XCTAssertEqual(recs, ["Helvetica"])
    }

    func testReset() async throws {
        let store = try PreferenceStore(directory: directory)
        try await store.set(font: "Avenir")
        try await store.recordUse(of: "Neon", category: .effect)
        try await store.reset()
        let prefs = await store.current
        XCTAssertEqual(prefs, UserPreferences())
        let reloaded = try PreferenceStore(directory: directory)
        let reloadedPrefs = await reloaded.current
        XCTAssertEqual(reloadedPrefs, UserPreferences(), "reset must persist")
    }

    func testRecommendationLimit() async throws {
        let store = try PreferenceStore(directory: directory)
        for i in 0..<10 {
            try await store.recordUse(of: "Effect \(i)", category: .effect)
        }
        let recs = await store.recommendations(for: .effect, limit: 3)
        XCTAssertEqual(recs.count, 3)
    }
}
