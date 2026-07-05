import Foundation
import GhostlyCore
import GhostlyDomain

/// File-backed `ProjectRepository`: each project is an atomic JSON envelope,
/// with bounded per-project version-history snapshots and a separate autosave
/// slot for crash recovery. Cross-platform (pure Foundation) and serialized
/// through an actor so concurrent saves can't corrupt a file.
///
/// Layout under `root`:
/// ```
/// projects/<id>.json          canonical saved state
/// snapshots/<id>/<millis>.json version history (newest kept, oldest pruned)
/// autosave/<id>.json           latest unsaved recovery copy
/// ```
public actor FileProjectStore: ProjectRepository {
    private let root: URL
    private let maxSnapshots: Int
    private let fileManager = FileManager.default

    public init(root: URL, maxSnapshots: Int = 20) throws {
        precondition(maxSnapshots > 0, "maxSnapshots must be positive")
        self.root = root
        self.maxSnapshots = maxSnapshots
        for sub in ["projects", "snapshots", "autosave"] {
            try fileManager.createDirectory(at: root.appendingPathComponent(sub),
                                            withIntermediateDirectories: true)
        }
    }

    // MARK: Save / load

    public func save(_ project: Project) async throws {
        let envelope = StoredProject(project: project)
        let data = try encode(envelope)
        try write(data, to: projectURL(project.id))
        try writeSnapshot(data, for: project.id, at: envelope.savedAt)
        // A successful save supersedes any pending autosave.
        try? fileManager.removeItem(at: autosaveURL(project.id))
    }

    public func load(_ id: ProjectID) async throws -> Project {
        let url = projectURL(id)
        guard fileManager.fileExists(atPath: url.path) else {
            throw StudioError.notFound(entity: "Project", id: id.rawValue)
        }
        return try decodeEnvelope(at: url).migratedToCurrent().project
    }

    public func list() async throws -> [ProjectSummary] {
        let dir = root.appendingPathComponent("projects")
        let files = (try? fileManager.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        var summaries: [ProjectSummary] = []
        for file in files where file.pathExtension == "json" {
            guard let envelope = try? decodeEnvelope(at: file).migratedToCurrent() else { continue }
            let timeline = envelope.project.timeline
            summaries.append(ProjectSummary(
                id: envelope.project.id, name: envelope.project.name,
                savedAt: envelope.savedAt,
                durationSeconds: timeline.duration.seconds,
                clipCount: timeline.clips.count))
        }
        return summaries.sorted { $0.savedAt > $1.savedAt }
    }

    public func delete(_ id: ProjectID) async throws {
        let url = projectURL(id)
        guard fileManager.fileExists(atPath: url.path) else {
            throw StudioError.notFound(entity: "Project", id: id.rawValue)
        }
        try fileManager.removeItem(at: url)
        try? fileManager.removeItem(at: snapshotDir(id))
        try? fileManager.removeItem(at: autosaveURL(id))
    }

    // MARK: Snapshots / version history

    public func snapshots(for id: ProjectID) async throws -> [Snapshot] {
        let dir = snapshotDir(id)
        let files = (try? fileManager.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        return files
            .filter { $0.pathExtension == "json" }
            .compactMap { file -> Snapshot? in
                let stamp = file.deletingPathExtension().lastPathComponent
                guard let millis = Int64(stamp) else { return nil }
                return Snapshot(id: stamp, savedAt: Date(timeIntervalSince1970: Double(millis) / 1000))
            }
            .sorted { $0.id > $1.id } // newest first (lexation-safe: fixed-width epoch)
    }

    @discardableResult
    public func restore(_ id: ProjectID, snapshot: String) async throws -> Project {
        let url = snapshotDir(id).appendingPathComponent("\(snapshot).json")
        guard fileManager.fileExists(atPath: url.path) else {
            throw StudioError.notFound(entity: "Snapshot", id: snapshot)
        }
        let project = try decodeEnvelope(at: url).migratedToCurrent().project
        try await save(project) // restoring is itself a new saved version
        return project
    }

    // MARK: Autosave / recovery

    public func autosave(_ project: Project) async throws {
        try write(try encode(StoredProject(project: project)), to: autosaveURL(project.id))
    }

    public func recoverAutosave(_ id: ProjectID) async throws -> Project? {
        let autosave = autosaveURL(id)
        guard fileManager.fileExists(atPath: autosave.path) else { return nil }
        let autosaveEnvelope = try decodeEnvelope(at: autosave).migratedToCurrent()
        // Only offer the autosave if it's newer than the canonical save.
        let saved = projectURL(id)
        if fileManager.fileExists(atPath: saved.path),
           let savedEnvelope = try? decodeEnvelope(at: saved),
           savedEnvelope.savedAt >= autosaveEnvelope.savedAt {
            return nil
        }
        return autosaveEnvelope.project
    }

    // MARK: Internals

    private func writeSnapshot(_ data: Data, for id: ProjectID, at date: Date) throws {
        let dir = snapshotDir(id)
        try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        let millis = Int64(date.timeIntervalSince1970 * 1000)
        try write(data, to: dir.appendingPathComponent("\(millis).json"))
        pruneSnapshots(in: dir)
    }

    private func pruneSnapshots(in dir: URL) {
        let files = (try? fileManager.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        let jsons = files.filter { $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent > $1.lastPathComponent } // newest first
        guard jsons.count > maxSnapshots else { return }
        for stale in jsons[maxSnapshots...] {
            try? fileManager.removeItem(at: stale)
        }
    }

    private func projectURL(_ id: ProjectID) -> URL {
        root.appendingPathComponent("projects").appendingPathComponent("\(safe(id)).json")
    }

    private func snapshotDir(_ id: ProjectID) -> URL {
        root.appendingPathComponent("snapshots").appendingPathComponent(safe(id))
    }

    private func autosaveURL(_ id: ProjectID) -> URL {
        root.appendingPathComponent("autosave").appendingPathComponent("\(safe(id)).json")
    }

    /// Sanitizes an id for use as a filename.
    private func safe(_ id: ProjectID) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let scalars = id.rawValue.unicodeScalars.map { allowed.contains($0) ? Character($0) : "_" }
        let name = String(scalars)
        return name.isEmpty ? "project" : name
    }

    private func encode(_ envelope: StoredProject) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        do {
            return try encoder.encode(envelope)
        } catch {
            throw StudioError.io(path: envelope.project.id.rawValue, detail: error.localizedDescription)
        }
    }

    private func decodeEnvelope(at url: URL) throws -> StoredProject {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw StudioError.io(path: url.path, detail: error.localizedDescription)
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            return try decoder.decode(StoredProject.self, from: data)
        } catch {
            throw StudioError.parseFailure(format: "StoredProject", detail: error.localizedDescription)
        }
    }

    private func write(_ data: Data, to url: URL) throws {
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            throw StudioError.io(path: url.path, detail: error.localizedDescription)
        }
    }
}
