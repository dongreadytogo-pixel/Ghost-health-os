import Foundation
import GhostlyCore

/// Plugin lifecycle states and their legal transitions
/// (docs/knowledge/14-plugin-sdk.md):
/// `discovered → validated → loaded → activated ⇄ deactivated → unloaded`.
public enum PluginState: String, Sendable, Equatable, CaseIterable {
    case discovered, validated, loaded, activated, deactivated, unloaded, failed

    /// States reachable from this one.
    public var legalNextStates: Set<PluginState> {
        switch self {
        case .discovered: return [.validated, .failed]
        case .validated: return [.loaded, .failed]
        case .loaded: return [.activated, .unloaded, .failed]
        case .activated: return [.deactivated, .failed]
        case .deactivated: return [.activated, .unloaded, .failed]
        case .unloaded, .failed: return []
        }
    }
}

/// A registered plugin with its current lifecycle state.
public struct PluginRecord: Sendable, Equatable, Identifiable {
    public let manifest: PluginManifest
    public var state: PluginState
    /// Why the plugin is `.failed`, when it is.
    public var failureReason: String?

    public var id: String { manifest.id }

    public init(manifest: PluginManifest, state: PluginState = .discovered) {
        self.manifest = manifest
        self.state = state
        self.failureReason = nil
    }
}

/// Owns every known plugin and drives lifecycle transitions with full
/// legality checking. Actual code loading is a host concern injected later
/// (XPC/ExtensionKit); the registry is the bookkeeping heart the host and
/// marketplace both drive.
public actor PluginRegistry {
    public let studioVersion: SemanticVersion
    private var records: [String: PluginRecord] = [:]
    private var order: [String] = []
    private let logger: GhostlyCore.Logger

    public init(studioVersion: SemanticVersion,
                logger: GhostlyCore.Logger = .init(subsystem: "PluginRegistry")) {
        self.studioVersion = studioVersion
        self.logger = logger
    }

    public var allPlugins: [PluginRecord] { order.compactMap { records[$0] } }
    public var activePlugins: [PluginRecord] { allPlugins.filter { $0.state == .activated } }

    public func plugin(_ id: String) -> PluginRecord? { records[id] }

    /// Registers a discovered plugin. Duplicate ids are rejected: a plugin
    /// identity may exist once; upgrades go through unload + re-discover.
    public func discover(_ manifest: PluginManifest) throws {
        guard records[manifest.id] == nil else {
            throw StudioError.invalidInput(field: "id",
                reason: "plugin '\(manifest.id)' is already registered")
        }
        records[manifest.id] = PluginRecord(manifest: manifest)
        order.append(manifest.id)
        logger.info("discovered plugin \(manifest.id) v\(manifest.version)")
    }

    /// Validates manifest rules + studio-version compatibility.
    public func validate(_ id: String) throws {
        try transition(id) { record in
            try record.manifest.validate()
            guard record.manifest.isCompatible(withStudio: studioVersion) else {
                throw StudioError.invalidInput(field: "minStudioVersion",
                    reason: "plugin requires studio \(record.manifest.minStudioVersion), running \(studioVersion)")
            }
            return .validated
        }
    }

    public func load(_ id: String) throws {
        try transition(id) { _ in .loaded }
    }

    public func activate(_ id: String) throws {
        try transition(id) { _ in .activated }
    }

    public func deactivate(_ id: String) throws {
        try transition(id) { _ in .deactivated }
    }

    public func unload(_ id: String) throws {
        try transition(id) { _ in .unloaded }
    }

    /// Removes an unloaded/failed plugin so a new version can be discovered.
    public func remove(_ id: String) throws {
        guard let record = records[id] else {
            throw StudioError.notFound(entity: "Plugin", id: id)
        }
        guard record.state == .unloaded || record.state == .failed else {
            throw StudioError.invalidInput(field: "state",
                reason: "cannot remove plugin in state '\(record.state.rawValue)'; unload it first")
        }
        records.removeValue(forKey: id)
        order.removeAll { $0 == id }
    }

    /// Active contributions of a kind, in registration order — what the
    /// studio's registries (tools, styles, presets) consume.
    public func contributors(of kind: ContributionKind) -> [PluginManifest] {
        activePlugins.map(\.manifest).filter { $0.contributes.contains(kind) }
    }

    // MARK: Internals

    /// Runs a transition. A failure of the transition *work* (e.g. manifest
    /// validation) marks the plugin `.failed` with the reason recorded; a
    /// merely illegal transition request leaves the plugin's state untouched.
    private func transition(_ id: String,
                            _ body: (PluginRecord) throws -> PluginState) throws {
        guard var record = records[id] else {
            throw StudioError.notFound(entity: "Plugin", id: id)
        }
        let next: PluginState
        do {
            next = try body(record)
        } catch {
            if record.state.legalNextStates.contains(.failed) {
                record.state = .failed
                record.failureReason = (error as? StudioError)?.errorDescription
                    ?? error.localizedDescription
                records[id] = record
            }
            throw error
        }
        guard record.state.legalNextStates.contains(next) else {
            throw StudioError.invalidInput(field: "state",
                reason: "illegal transition \(record.state.rawValue) → \(next.rawValue) for '\(id)'")
        }
        record.state = next
        records[id] = record
        logger.debug("plugin \(id) → \(next.rawValue)")
    }
}
