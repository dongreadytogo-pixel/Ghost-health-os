import Foundation
import GhostlyCore

/// Semantic version (`MAJOR.MINOR.PATCH`) — the plugin/SDK compatibility
/// currency. See docs/knowledge/14-plugin-sdk.md.
public struct SemanticVersion: Hashable, Sendable, Comparable, CustomStringConvertible, Codable {
    public let major: Int
    public let minor: Int
    public let patch: Int

    public init(_ major: Int, _ minor: Int, _ patch: Int) {
        precondition(major >= 0 && minor >= 0 && patch >= 0, "version parts must be non-negative")
        self.major = major
        self.minor = minor
        self.patch = patch
    }

    /// Parses `"1.2.3"` (also tolerates `"1"` and `"1.2"`, zero-filling).
    public init?(_ string: String) {
        let parts = string.split(separator: ".", omittingEmptySubsequences: false)
        guard (1...3).contains(parts.count) else { return nil }
        var numbers: [Int] = []
        for part in parts {
            guard let n = Int(part), n >= 0 else { return nil }
            numbers.append(n)
        }
        while numbers.count < 3 { numbers.append(0) }
        self.init(numbers[0], numbers[1], numbers[2])
    }

    public static func < (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
        (lhs.major, lhs.minor, lhs.patch) < (rhs.major, rhs.minor, rhs.patch)
    }

    public var description: String { "\(major).\(minor).\(patch)" }

    // Encoded as the string form ("1.2.3") for manifest friendliness.
    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        guard let parsed = SemanticVersion(raw) else {
            throw StudioError.parseFailure(format: "SemanticVersion", detail: "invalid version '\(raw)'")
        }
        self = parsed
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(description)
    }
}

/// A capability a plugin must declare to use.
public enum PluginPermission: String, Sendable, Codable, CaseIterable {
    case filesystemRead = "filesystem.read"
    case filesystemWrite = "filesystem.write"
    case network = "network"
    case fcpAutomation = "fcp.automation"
}

/// What a plugin contributes into the studio's registries.
public enum ContributionKind: String, Sendable, Codable, CaseIterable {
    case mcpTools, captionStyles, renderPresets, pacingProfiles,
         detectionProviders, llmProviders, motionTemplates
}

/// The `plugin.json` contract (docs/knowledge/14-plugin-sdk.md).
public struct PluginManifest: Sendable, Codable, Equatable, Identifiable {
    public var id: String
    public var name: String
    public var version: SemanticVersion
    public var minStudioVersion: SemanticVersion
    public var author: String
    public var entryPoint: String
    public var permissions: [PluginPermission]
    public var contributes: [ContributionKind]

    public init(id: String, name: String, version: SemanticVersion,
                minStudioVersion: SemanticVersion, author: String, entryPoint: String,
                permissions: [PluginPermission] = [], contributes: [ContributionKind] = []) {
        self.id = id
        self.name = name
        self.version = version
        self.minStudioVersion = minStudioVersion
        self.author = author
        self.entryPoint = entryPoint
        self.permissions = permissions
        self.contributes = contributes
    }

    /// Decodes and validates a `plugin.json`.
    public static func parse(_ data: Data) throws -> PluginManifest {
        let manifest: PluginManifest
        do {
            manifest = try JSONDecoder().decode(PluginManifest.self, from: data)
        } catch let error as StudioError {
            throw error
        } catch {
            throw StudioError.parseFailure(format: "plugin.json", detail: describeDecodingError(error))
        }
        try manifest.validate()
        return manifest
    }

    /// Structural validation beyond decoding.
    public func validate() throws {
        // Reverse-DNS id: at least two dot-separated lowercase segments.
        let segments = id.split(separator: ".")
        let valid = segments.count >= 2 && segments.allSatisfy { segment in
            !segment.isEmpty && segment.allSatisfy { $0.isLowercase || $0.isNumber || $0 == "-" }
        }
        guard valid else {
            throw StudioError.invalidInput(field: "id",
                reason: "'\(id)' is not a reverse-DNS identifier (e.g. com.example.pack)")
        }
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw StudioError.invalidInput(field: "name", reason: "must not be empty")
        }
        guard !entryPoint.isEmpty, !entryPoint.contains("/"), !entryPoint.contains("..") else {
            throw StudioError.invalidInput(field: "entryPoint",
                reason: "must be a bare bundle name inside the plugin package")
        }
        guard !contributes.isEmpty else {
            throw StudioError.invalidInput(field: "contributes",
                reason: "plugin must declare at least one contribution")
        }
    }

    /// True when this plugin may run on the given studio version.
    public func isCompatible(withStudio studioVersion: SemanticVersion) -> Bool {
        studioVersion >= minStudioVersion
    }

    private static func describeDecodingError(_ error: Error) -> String {
        if case let DecodingError.keyNotFound(key, _) = error {
            return "missing required field '\(key.stringValue)'"
        }
        return "not a valid plugin manifest"
    }
}
