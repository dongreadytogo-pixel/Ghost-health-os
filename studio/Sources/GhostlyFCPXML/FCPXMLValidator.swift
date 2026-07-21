import Foundation
import GhostlyCore
import GhostlyDomain

/// Structural validator for FCPXML documents — the gate every generated
/// document passes before it is offered to Final Cut Pro.
public struct FCPXMLValidator {
    public struct Issue: Equatable, Sendable, CustomStringConvertible {
        public enum Severity: String, Sendable { case error, warning }
        public let severity: Severity
        public let message: String

        public var description: String { "[\(severity.rawValue)] \(message)" }
    }

    public static let supportedVersions: Set<String> = ["1.9", "1.10", "1.11", "1.12", "1.13"]

    /// Elements whose `ref` must resolve to a resource id.
    private static let referencingElements: Set<String> = [
        "asset-clip", "video", "audio", "ref-clip", "filter-video", "filter-audio", "title",
    ]

    /// Attributes carrying FCPXML rational-time values.
    private static let timeAttributes: Set<String> = [
        "offset", "duration", "start", "tcStart", "frameDuration",
    ]

    public init() {}

    public func validate(_ document: String) -> [Issue] {
        let root: XML
        do {
            root = try XMLDocumentParser.parse(document)
        } catch {
            return [Issue(severity: .error, message: "not well-formed XML: \(error.localizedDescription)")]
        }
        return validate(root)
    }

    public func validate(_ root: XML) -> [Issue] {
        var issues: [Issue] = []

        guard root.name == "fcpxml" else {
            return [Issue(severity: .error, message: "root element is <\(root.name)>, expected <fcpxml>")]
        }
        if let version = root[attribute: "version"] {
            if !Self.supportedVersions.contains(version) {
                issues.append(Issue(severity: .warning, message: "unrecognized fcpxml version '\(version)'"))
            }
        } else {
            issues.append(Issue(severity: .error, message: "<fcpxml> is missing the version attribute"))
        }

        // Collect resource ids.
        var resourceIDs = Set<String>()
        if let resources = root.first("resources") {
            for resource in resources.children {
                if let id = resource[attribute: "id"] {
                    if !resourceIDs.insert(id).inserted {
                        issues.append(Issue(severity: .error, message: "duplicate resource id '\(id)'"))
                    }
                } else {
                    issues.append(Issue(severity: .error, message: "<\(resource.name)> resource has no id"))
                }
            }
        } else {
            issues.append(Issue(severity: .warning, message: "document has no <resources> section"))
        }

        walk(root, resourceIDs: resourceIDs, issues: &issues)

        for sequence in root.descendants("sequence") {
            validateSequence(sequence, issues: &issues)
        }
        return issues
    }

    /// True when the document has no `.error`-severity issues.
    public func isAcceptable(_ document: String) -> Bool {
        !validate(document).contains { $0.severity == .error }
    }

    // MARK: Internals

    private func walk(_ element: XML, resourceIDs: Set<String>, issues: inout [Issue]) {
        if Self.referencingElements.contains(element.name),
           let ref = element[attribute: "ref"], !resourceIDs.contains(ref) {
            issues.append(Issue(severity: .error,
                                message: "<\(element.name)> references undefined resource '\(ref)'"))
        }
        if element.name == "sequence", let format = element[attribute: "format"],
           !resourceIDs.contains(format) {
            issues.append(Issue(severity: .error,
                                message: "<sequence> references undefined format '\(format)'"))
        }
        for (key, value) in element.attributes where Self.timeAttributes.contains(key) {
            if RationalTime(fcpxml: value) == nil {
                issues.append(Issue(severity: .error,
                                    message: "<\(element.name)> has malformed time \(key)=\"\(value)\""))
            }
        }
        for child in element.children {
            walk(child, resourceIDs: resourceIDs, issues: &issues)
        }
    }

    private func validateSequence(_ sequence: XML, issues: inout [Issue]) {
        if sequence[attribute: "format"] == nil {
            issues.append(Issue(severity: .error, message: "<sequence> is missing its format"))
        }
        guard let spine = sequence.first("spine") else {
            issues.append(Issue(severity: .warning, message: "<sequence> has no <spine>"))
            return
        }
        // Storyline elements must tile [0, duration) without overlap.
        var cursor = RationalTime.zero
        for child in spine.children where child.name != "transition" {
            guard let offset = child[attribute: "offset"].flatMap(RationalTime.init(fcpxml:)),
                  let duration = child[attribute: "duration"].flatMap(RationalTime.init(fcpxml:))
            else { continue }
            if offset != cursor {
                let relation = offset > cursor ? "leaves a gap" : "overlaps"
                issues.append(Issue(severity: .error,
                    message: "spine element <\(child.name)> at \(offset) \(relation) (expected \(cursor))"))
            }
            cursor = max(cursor, offset + duration)
        }
    }
}
