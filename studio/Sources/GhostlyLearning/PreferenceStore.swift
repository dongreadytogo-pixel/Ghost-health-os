import Foundation
import GhostlyCore

/// What the studio remembers about how this editor likes to work. Stored
/// locally as JSON — never transmitted (see AI MEMORY in the architecture).
public struct UserPreferences: Sendable, Codable, Equatable {
    public var preferredFont: String?
    public var preferredCaptionStyle: String?
    public var preferredTransition: String?
    public var preferredExportPreset: String?
    /// Usage counters with recency weighting, keyed by category.
    public var usage: [String: [UsageRecord]]
    /// Rolling history of prompts, newest last (bounded).
    public var recentPrompts: [String]

    public struct UsageRecord: Sendable, Codable, Equatable {
        public var value: String
        public var count: Int
        public var lastUsed: Date

        public init(value: String, count: Int, lastUsed: Date) {
            self.value = value
            self.count = count
            self.lastUsed = lastUsed
        }
    }

    public init() {
        usage = [:]
        recentPrompts = []
    }

    public enum Category: String, Sendable, CaseIterable {
        case font, captionStyle, transition, effect, lut, exportPreset, asset, pacingStyle
    }
}

/// Thread-safe local preference store with atomic JSON persistence.
public actor PreferenceStore {
    public static let maxRecentPrompts = 50

    private let fileURL: URL
    private var preferences: UserPreferences
    private let logger: GhostlyCore.Logger

    /// - Parameter directory: storage directory; created if missing.
    public init(directory: URL, logger: GhostlyCore.Logger = .init(subsystem: "PreferenceStore")) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        self.fileURL = directory.appendingPathComponent("preferences.json")
        self.logger = logger
        if let data = try? Data(contentsOf: fileURL) {
            do {
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                self.preferences = try decoder.decode(UserPreferences.self, from: data)
            } catch {
                // A corrupt file must not brick the app: start fresh but keep
                // the damaged file for inspection.
                let backup = fileURL.appendingPathExtension("corrupt")
                try? FileManager.default.removeItem(at: backup)
                try? FileManager.default.moveItem(at: fileURL, to: backup)
                self.preferences = UserPreferences()
            }
        } else {
            self.preferences = UserPreferences()
        }
    }

    public var current: UserPreferences { preferences }

    // MARK: Recording

    public func recordUse(of value: String, category: UserPreferences.Category,
                          at date: Date = Date()) throws {
        var records = preferences.usage[category.rawValue] ?? []
        if let index = records.firstIndex(where: { $0.value == value }) {
            records[index].count += 1
            records[index].lastUsed = date
        } else {
            records.append(.init(value: value, count: 1, lastUsed: date))
        }
        preferences.usage[category.rawValue] = records
        try persist()
    }

    public func recordPrompt(_ prompt: String) throws {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        preferences.recentPrompts.removeAll { $0 == trimmed }
        preferences.recentPrompts.append(trimmed)
        if preferences.recentPrompts.count > Self.maxRecentPrompts {
            preferences.recentPrompts.removeFirst(
                preferences.recentPrompts.count - Self.maxRecentPrompts)
        }
        try persist()
    }

    public func set(font: String? = nil, captionStyle: String? = nil,
                    transition: String? = nil, exportPreset: String? = nil) throws {
        if let font { preferences.preferredFont = font }
        if let captionStyle { preferences.preferredCaptionStyle = captionStyle }
        if let transition { preferences.preferredTransition = transition }
        if let exportPreset { preferences.preferredExportPreset = exportPreset }
        try persist()
    }

    // MARK: Recommendations

    /// Top values for a category, ranked by frequency with exponential
    /// recency decay (half-life 30 days) so tastes can change.
    public func recommendations(for category: UserPreferences.Category,
                                limit: Int = 5, now: Date = Date()) -> [String] {
        let records = preferences.usage[category.rawValue] ?? []
        let halfLife: TimeInterval = 30 * 24 * 3600
        return records
            .map { record -> (String, Double) in
                let age = max(0, now.timeIntervalSince(record.lastUsed))
                let decay = pow(0.5, age / halfLife)
                return (record.value, Double(record.count) * decay)
            }
            .sorted { $0.1 > $1.1 }
            .prefix(limit)
            .map(\.0)
    }

    /// Clears everything — the user's "forget me" button.
    public func reset() throws {
        preferences = UserPreferences()
        try persist()
    }

    // MARK: Persistence

    private func persist() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(preferences)
        do {
            try data.write(to: fileURL, options: .atomic)
        } catch {
            logger.error("failed to persist preferences: \(error.localizedDescription)")
            throw StudioError.io(path: fileURL.path, detail: error.localizedDescription)
        }
    }
}
