#if canImport(SwiftUI)
import Foundation
import SwiftUI
import GhostlyCore
import GhostlyDomain
import GhostlyDirector
import GhostlyLearning

/// One unit of work visible in the task queue panel.
public struct StudioTask: Identifiable, Sendable {
    public enum Status: String, Sendable {
        case queued, running, done, failed
    }

    public let id = UUID()
    public var title: String
    public var status: Status
    public var detail: String

    public init(title: String, status: Status = .queued, detail: String = "") {
        self.title = title
        self.status = status
        self.detail = detail
    }
}

/// Root observable state of the studio app: prompt handling, the task
/// queue, logs, and learned preferences.
@MainActor
public final class StudioModel: ObservableObject {
    @Published public private(set) var tasks: [StudioTask] = []
    @Published public private(set) var logEntries: [String] = []
    @Published public private(set) var lastPlan: Director.Plan?
    @Published public var prompt: String = ""

    private let director = Director()
    private let preferences: PreferenceStore?

    public init() {
        let home = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".ghostly")
        self.preferences = try? PreferenceStore(directory: home)
    }

    /// Interprets the current prompt into an edit plan and enqueues it.
    public func submitPrompt() {
        let command = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !command.isEmpty else { return }
        prompt = ""
        do {
            let plan = try director.interpret(command)
            lastPlan = plan
            append(task: StudioTask(
                title: command,
                status: .done,
                detail: "→ \(plan.profile.style.rawValue), " +
                        "\(plan.profile.format.width)x\(plan.profile.format.height)" +
                        (plan.wantsCaptions ? ", captions: \(plan.profile.captionStyleName ?? "default")" : "")))
            log("interpreted '\(command)' as \(plan.intents.count) intent(s)")
            if let store = preferences {
                Task.detached {
                    try? await store.recordPrompt(command)
                    try? await store.recordUse(of: plan.profile.style.rawValue, category: .pacingStyle)
                }
            }
        } catch {
            append(task: StudioTask(title: command, status: .failed,
                                    detail: error.localizedDescription))
            log("could not interpret '\(command)': \(error.localizedDescription)")
        }
    }

    public func append(task: StudioTask) {
        tasks.insert(task, at: 0)
        if tasks.count > 200 { tasks.removeLast(tasks.count - 200) }
    }

    public func log(_ message: String) {
        logEntries.append("[\(Self.timestampFormatter.string(from: Date()))] \(message)")
        if logEntries.count > 500 { logEntries.removeFirst(logEntries.count - 500) }
    }

    private static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()
}
#endif
