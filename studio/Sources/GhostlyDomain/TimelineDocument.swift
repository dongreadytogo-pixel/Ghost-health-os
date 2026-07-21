import Foundation
import GhostlyCore

/// A domain event emitted whenever a document's timeline changes. UI layers
/// and the learning system subscribe to these instead of polling.
public enum DomainEvent: Sendable, Equatable {
    case commandApplied(name: String)
    case undone(name: String)
    case redone(name: String)
    case reset
}

/// An editable timeline with full undo/redo history and change notification.
///
/// This is the application-facing aggregate root: all mutations go through
/// `perform(_:)` so every change is reversible and observable. The undo and
/// redo stacks follow the standard rule — performing a new command clears the
/// redo stack.
public final class TimelineDocument: @unchecked Sendable {
    public private(set) var timeline: Timeline
    public var maxHistoryDepth: Int

    private var undoStack: [EditCommand] = []
    private var redoStack: [EditCommand] = []
    private var subscribers: [(DomainEvent) -> Void] = []
    private let lock = NSLock()

    public init(timeline: Timeline, maxHistoryDepth: Int = 200) {
        precondition(maxHistoryDepth > 0, "history depth must be positive")
        self.timeline = timeline
        self.maxHistoryDepth = maxHistoryDepth
    }

    public var canUndo: Bool { withLock { !undoStack.isEmpty } }
    public var canRedo: Bool { withLock { !redoStack.isEmpty } }

    /// Names of undoable commands, oldest first (for menu display/testing).
    public var undoableCommandNames: [String] { withLock { undoStack.map(\.name) } }

    /// Applies a command, pushing it onto the undo stack and clearing redo.
    /// If the command throws, the timeline is left unchanged.
    public func perform(_ command: EditCommand) throws {
        try withLock {
            var candidate = timeline
            try command.apply(to: &candidate)
            timeline = candidate
            undoStack.append(command)
            if undoStack.count > maxHistoryDepth {
                undoStack.removeFirst(undoStack.count - maxHistoryDepth)
            }
            redoStack.removeAll()
        }
        emit(.commandApplied(name: command.name))
    }

    /// Reverts the most recent command. No-op (returns false) when nothing to undo.
    @discardableResult
    public func undo() throws -> Bool {
        let name: String? = try withLock {
            guard let command = undoStack.last else { return nil }
            var candidate = timeline
            try command.revert(from: &candidate)
            timeline = candidate
            undoStack.removeLast()
            redoStack.append(command)
            return command.name
        }
        guard let name else { return false }
        emit(.undone(name: name))
        return true
    }

    /// Re-applies the most recently undone command.
    @discardableResult
    public func redo() throws -> Bool {
        let name: String? = try withLock {
            guard let command = redoStack.last else { return nil }
            var candidate = timeline
            try command.apply(to: &candidate)
            timeline = candidate
            redoStack.removeLast()
            undoStack.append(command)
            return command.name
        }
        guard let name else { return false }
        emit(.redone(name: name))
        return true
    }

    /// Replaces the timeline wholesale and clears history (e.g. after import).
    public func reset(to timeline: Timeline) {
        withLock {
            self.timeline = timeline
            undoStack.removeAll()
            redoStack.removeAll()
        }
        emit(.reset)
    }

    /// Registers an observer for domain events. Not removable — intended for
    /// the lifetime of the document's owner.
    public func subscribe(_ handler: @escaping (DomainEvent) -> Void) {
        withLock { subscribers.append(handler) }
    }

    // MARK: Internals

    private func emit(_ event: DomainEvent) {
        let handlers = withLock { subscribers }
        for handler in handlers { handler(event) }
    }

    private func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        return try body()
    }
}
