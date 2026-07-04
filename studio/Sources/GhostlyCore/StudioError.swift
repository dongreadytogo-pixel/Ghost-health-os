import Foundation

/// The single error currency of the studio. Every module maps its failures
/// into one of these cases so callers (UI, MCP, CLI) can present and route
/// errors uniformly without unwrapping module-specific types.
public enum StudioError: Error, Equatable, Sendable {
    /// Input from the user or an agent failed validation.
    case invalidInput(field: String, reason: String)
    /// A referenced entity (asset, project, preset…) does not exist.
    case notFound(entity: String, id: String)
    /// Parsing external data (FCPXML, SRT, JSON-RPC…) failed.
    case parseFailure(format: String, detail: String)
    /// Generated output failed its own validation gate.
    case validationFailure(detail: String)
    /// An I/O operation failed.
    case io(path: String, detail: String)
    /// A remote AI provider returned an error.
    case provider(name: String, detail: String)
    /// The operation is not supported on the current platform.
    case unsupportedPlatform(operation: String)
    /// An internal invariant was broken — always a bug, never user error.
    case invariant(detail: String)
}

extension StudioError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case let .invalidInput(field, reason):
            return "Invalid input for '\(field)': \(reason)"
        case let .notFound(entity, id):
            return "\(entity) '\(id)' was not found"
        case let .parseFailure(format, detail):
            return "Could not parse \(format): \(detail)"
        case let .validationFailure(detail):
            return "Validation failed: \(detail)"
        case let .io(path, detail):
            return "I/O error at '\(path)': \(detail)"
        case let .provider(name, detail):
            return "AI provider '\(name)' failed: \(detail)"
        case let .unsupportedPlatform(operation):
            return "'\(operation)' is not supported on this platform"
        case let .invariant(detail):
            return "Internal error: \(detail)"
        }
    }

    /// Stable machine-readable code for MCP/API surfaces.
    public var code: String {
        switch self {
        case .invalidInput: return "invalid_input"
        case .notFound: return "not_found"
        case .parseFailure: return "parse_failure"
        case .validationFailure: return "validation_failure"
        case .io: return "io_error"
        case .provider: return "provider_error"
        case .unsupportedPlatform: return "unsupported_platform"
        case .invariant: return "internal_error"
        }
    }
}
