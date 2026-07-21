import XCTest
import GhostlyCore
import GhostlyDomain
@testable import GhostlyStorage

final class FileProjectStoreTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ghostly-storage-\(UUID().uuidString)")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func makeProject(name: String = "Demo", clips: Int = 1,
                             id: ProjectID = ProjectID()) -> Project {
        var timeline = Timeline(name: name, format: .hd1080p30)
        let asset = AssetID()
        for i in 0..<clips {
            timeline.appendToStoryline(assetID: asset, name: "C\(i)",
                sourceRange: TimeRange(start: .zero, duration: RationalTime(seconds: 5)))
        }
        return Project(id: id, name: name, timeline: timeline)
    }

    // MARK: Save / load

    func testSaveAndLoadRoundTrip() async throws {
        let store = try FileProjectStore(root: root)
        let project = makeProject(name: "Round", clips: 3)
        try await store.save(project)
        let loaded = try await store.load(project.id)
        XCTAssertEqual(loaded.id, project.id)
        XCTAssertEqual(loaded.name, "Round")
        XCTAssertEqual(loaded.timeline.clips.count, 3)
    }

    func testLoadMissingThrowsNotFound() async {
        let store = try! FileProjectStore(root: root)
        do {
            _ = try await store.load(ProjectID("ghost"))
            XCTFail("expected notFound")
        } catch let StudioError.notFound(entity, _) {
            XCTAssertEqual(entity, "Project")
        } catch {
            XCTFail("wrong error: \(error)")
        }
    }

    func testListSummariesSortedBySavedAt() async throws {
        let store = try FileProjectStore(root: root)
        try await store.save(makeProject(name: "First", clips: 1))
        try await store.save(makeProject(name: "Second", clips: 2))
        let summaries = try await store.list()
        XCTAssertEqual(summaries.count, 2)
        XCTAssertEqual(summaries.first?.name, "Second", "newest first")
        XCTAssertEqual(summaries.first?.clipCount, 2)
        XCTAssertEqual(summaries.first?.durationSeconds, 10)
    }

    func testDeleteRemovesProjectAndHistory() async throws {
        let store = try FileProjectStore(root: root)
        let project = makeProject()
        try await store.save(project)
        try await store.delete(project.id)
        let list = try await store.list()
        XCTAssertTrue(list.isEmpty)
        let snaps = try await store.snapshots(for: project.id)
        XCTAssertTrue(snaps.isEmpty)
        do {
            _ = try await store.load(project.id)
            XCTFail("expected notFound after delete")
        } catch { /* expected */ }
    }

    func testDeleteMissingThrows() async {
        let store = try! FileProjectStore(root: root)
        do {
            try await store.delete(ProjectID("nope"))
            XCTFail("expected notFound")
        } catch { /* expected */ }
    }

    // MARK: Persistence across instances

    func testDataSurvivesNewStoreInstance() async throws {
        let id = ProjectID()
        do {
            let store = try FileProjectStore(root: root)
            try await store.save(makeProject(name: "Persisted", id: id))
        }
        let reopened = try FileProjectStore(root: root)
        let loaded = try await reopened.load(id)
        XCTAssertEqual(loaded.name, "Persisted")
    }

    // MARK: Snapshots / version history

    func testEachSaveAddsSnapshot() async throws {
        let store = try FileProjectStore(root: root)
        let id = ProjectID()
        for i in 1...3 {
            try await store.save(makeProject(name: "v\(i)", clips: i, id: id))
            try await Task.sleep(nanoseconds: 2_000_000) // ensure distinct millis
        }
        let snaps = try await store.snapshots(for: id)
        XCTAssertEqual(snaps.count, 3)
        // Newest first.
        XCTAssertGreaterThan(snaps[0].savedAt, snaps[1].savedAt)
    }

    func testSnapshotsAreBounded() async throws {
        let store = try FileProjectStore(root: root, maxSnapshots: 3)
        let id = ProjectID()
        for i in 0..<6 {
            try await store.save(makeProject(name: "v\(i)", clips: 1, id: id))
            try await Task.sleep(nanoseconds: 2_000_000)
        }
        let snaps = try await store.snapshots(for: id)
        XCTAssertEqual(snaps.count, 3, "old snapshots must be pruned")
    }

    func testRestoreSnapshotBringsBackOlderState() async throws {
        let store = try FileProjectStore(root: root)
        let id = ProjectID()
        try await store.save(makeProject(name: "one clip", clips: 1, id: id))
        try await Task.sleep(nanoseconds: 3_000_000)
        try await store.save(makeProject(name: "five clips", clips: 5, id: id))

        let snaps = try await store.snapshots(for: id)
        XCTAssertEqual(snaps.count, 2)
        let oldest = snaps.last!  // the 1-clip version
        let restored = try await store.restore(id, snapshot: oldest.id)
        XCTAssertEqual(restored.timeline.clips.count, 1)
        // Restoring persists as the new canonical state.
        let loaded = try await store.load(id)
        XCTAssertEqual(loaded.timeline.clips.count, 1)
    }

    func testRestoreMissingSnapshotThrows() async throws {
        let store = try FileProjectStore(root: root)
        let project = makeProject()
        try await store.save(project)
        do {
            _ = try await store.restore(project.id, snapshot: "0")
            XCTFail("expected notFound")
        } catch let StudioError.notFound(entity, _) {
            XCTAssertEqual(entity, "Snapshot")
        } catch {
            XCTFail("wrong error: \(error)")
        }
    }

    // MARK: Autosave / recovery

    func testRecoverAutosaveWhenNewerThanSave() async throws {
        let store = try FileProjectStore(root: root)
        let id = ProjectID()
        try await store.save(makeProject(name: "saved", clips: 1, id: id))
        try await Task.sleep(nanoseconds: 3_000_000)
        try await store.autosave(makeProject(name: "autosaved", clips: 9, id: id))

        let recovered = try await store.recoverAutosave(id)
        XCTAssertEqual(recovered?.timeline.clips.count, 9)
    }

    func testSaveClearsAutosave() async throws {
        let store = try FileProjectStore(root: root)
        let id = ProjectID()
        try await store.autosave(makeProject(name: "draft", clips: 2, id: id))
        try await Task.sleep(nanoseconds: 3_000_000)
        try await store.save(makeProject(name: "committed", clips: 1, id: id))
        let recovered = try await store.recoverAutosave(id)
        XCTAssertNil(recovered, "a save newer than the autosave clears recovery")
    }

    func testRecoverAutosaveNilWhenNone() async throws {
        let store = try FileProjectStore(root: root)
        let recovered = try await store.recoverAutosave(ProjectID("none"))
        XCTAssertNil(recovered)
    }

    // MARK: Envelope / migration

    func testCorruptFileSurfacesParseError() async throws {
        let store = try FileProjectStore(root: root)
        let id = ProjectID("corrupt")
        let file = root.appendingPathComponent("projects").appendingPathComponent("corrupt.json")
        try Data("{not valid".utf8).write(to: file)
        do {
            _ = try await store.load(id)
            XCTFail("expected parse failure")
        } catch let StudioError.parseFailure(format, _) {
            XCTAssertEqual(format, "StoredProject")
        } catch {
            XCTFail("wrong error: \(error)")
        }
    }

    func testEnvelopeRejectsFutureSchema() throws {
        var envelope = StoredProject(project: makeProject())
        envelope.schemaVersion = StoredProject.currentSchemaVersion + 1
        XCTAssertThrowsError(try envelope.migratedToCurrent())
    }
}
