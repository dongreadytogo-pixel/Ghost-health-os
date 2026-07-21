import Foundation
import GhostlyCore
import GhostlyDomain

/// Lightweight listing entry for a stored project (avoids loading the whole
/// timeline just to show a browser row).
public struct ProjectSummary: Sendable, Codable, Equatable, Identifiable {
    public var id: ProjectID
    public var name: String
    public var savedAt: Date
    public var durationSeconds: Double
    public var clipCount: Int

    public init(id: ProjectID, name: String, savedAt: Date,
                durationSeconds: Double, clipCount: Int) {
        self.id = id
        self.name = name
        self.savedAt = savedAt
        self.durationSeconds = durationSeconds
        self.clipCount = clipCount
    }
}

/// A point-in-time recovery snapshot of a project.
public struct Snapshot: Sendable, Codable, Equatable, Identifiable {
    /// Sortable identifier (epoch milliseconds as a string).
    public var id: String
    public var savedAt: Date

    public init(id: String, savedAt: Date) {
        self.id = id
        self.savedAt = savedAt
    }
}

/// Persistence port for projects: save/load, listing, deletion, version
/// history (snapshots), and crash-recovery autosave. Adapters (file, SQLite,
/// cloud) implement this without the domain knowing how storage works.
public protocol ProjectRepository: Sendable {
    func save(_ project: Project) async throws
    func load(_ id: ProjectID) async throws -> Project
    func list() async throws -> [ProjectSummary]
    func delete(_ id: ProjectID) async throws

    /// Version history, newest first.
    func snapshots(for id: ProjectID) async throws -> [Snapshot]
    /// Restores a project to a snapshot's state (and returns it).
    @discardableResult
    func restore(_ id: ProjectID, snapshot: String) async throws -> Project

    /// Writes a fast crash-recovery copy without creating a snapshot.
    func autosave(_ project: Project) async throws
    /// The most recent autosave for a project, if newer than its saved state.
    func recoverAutosave(_ id: ProjectID) async throws -> Project?
}

/// Codable envelope wrapping a stored project with a schema version, so the
/// store can migrate older files forward without losing data.
struct StoredProject: Codable {
    static let currentSchemaVersion = 1

    var schemaVersion: Int
    var savedAt: Date
    var project: Project

    init(project: Project, savedAt: Date = Date()) {
        self.schemaVersion = Self.currentSchemaVersion
        self.savedAt = savedAt
        self.project = project
    }

    /// Migrates an older envelope to the current schema. Identity today; the
    /// hook exists so future schema bumps have one place to live.
    func migratedToCurrent() throws -> StoredProject {
        guard schemaVersion <= Self.currentSchemaVersion else {
            throw StudioError.parseFailure(
                format: "StoredProject",
                detail: "file schema v\(schemaVersion) is newer than supported v\(Self.currentSchemaVersion)")
        }
        return self
    }
}
