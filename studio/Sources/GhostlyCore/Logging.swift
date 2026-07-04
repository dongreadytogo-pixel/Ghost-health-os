import Foundation

/// Minimal structured logger. Backends are pluggable so the macOS app can
/// route to `os.Logger` while CLI/CI route to stderr, and tests can capture.
public enum LogLevel: Int, Comparable, Sendable, CustomStringConvertible {
    case debug = 0, info = 1, warning = 2, error = 3

    public static func < (lhs: LogLevel, rhs: LogLevel) -> Bool { lhs.rawValue < rhs.rawValue }

    public var description: String {
        switch self {
        case .debug: return "DEBUG"
        case .info: return "INFO"
        case .warning: return "WARN"
        case .error: return "ERROR"
        }
    }
}

public protocol LogBackend: Sendable {
    func write(level: LogLevel, subsystem: String, message: String)
}

/// Writes to standard error — safe for the MCP server, whose stdout is the
/// JSON-RPC channel and must never receive log noise.
public struct StderrLogBackend: LogBackend {
    public init() {}
    public func write(level: LogLevel, subsystem: String, message: String) {
        FileHandle.standardError.write(Data("[\(level)] \(subsystem): \(message)\n".utf8))
    }
}

/// Thread-safe in-memory backend for tests and the in-app log panel.
public final class MemoryLogBackend: LogBackend, @unchecked Sendable {
    public struct Entry: Sendable, Equatable {
        public let level: LogLevel
        public let subsystem: String
        public let message: String
    }

    private let lock = NSLock()
    private var storage: [Entry] = []

    public init() {}

    public func write(level: LogLevel, subsystem: String, message: String) {
        lock.lock()
        defer { lock.unlock() }
        storage.append(Entry(level: level, subsystem: subsystem, message: message))
    }

    public var entries: [Entry] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }
}

public struct Logger: Sendable {
    public let subsystem: String
    public var minimumLevel: LogLevel
    private let backend: any LogBackend

    public init(subsystem: String, minimumLevel: LogLevel = .info,
                backend: any LogBackend = StderrLogBackend()) {
        self.subsystem = subsystem
        self.minimumLevel = minimumLevel
        self.backend = backend
    }

    public func debug(_ message: @autoclosure () -> String) { log(.debug, message()) }
    public func info(_ message: @autoclosure () -> String) { log(.info, message()) }
    public func warning(_ message: @autoclosure () -> String) { log(.warning, message()) }
    public func error(_ message: @autoclosure () -> String) { log(.error, message()) }

    private func log(_ level: LogLevel, _ message: @autoclosure () -> String) {
        guard level >= minimumLevel else { return }
        backend.write(level: level, subsystem: subsystem, message: message())
    }
}
