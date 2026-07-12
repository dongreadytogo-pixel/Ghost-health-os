#if canImport(SwiftUI)
import Foundation
import SwiftUI
import GhostlyCore
import GhostlyDomain
import GhostlyDirector
import GhostlyDetection
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
    /// Path to a WAV recording; when set, "รันเวิร์กโฟลว์" runs the real
    /// analyze → edit → captions → export chain instead of just parsing intent.
    @Published public var audioPath: String = ""

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

    /// Runs the real end-to-end `Workflow` (analyze → edit → captions →
    /// export command) against `audioPath`, with AI memory when available.
    /// Progress is visible in the task queue: queued → running → done/failed.
    public func runWorkflow() {
        let command = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let path = audioPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !command.isEmpty, !path.isEmpty else { return }
        prompt = ""

        let task = StudioTask(title: "เวิร์กโฟลว์: \(command)", status: .running,
                              detail: "กำลังวิเคราะห์ \((path as NSString).lastPathComponent)…")
        let taskID = task.id
        append(task: task)
        log("เริ่มเวิร์กโฟลว์ '\(command)' บน \(path)")

        let store = preferences
        Task.detached { [weak self] in
            do {
                let audio = try WAV.decode(contentsOf: URL(fileURLWithPath: path))
                let request = Workflow.Request(audio: audio, command: command)
                let result: Workflow.Result
                if let store {
                    result = try await Workflow.run(request, memory: store)
                } else {
                    result = try Workflow.run(request)
                }
                await self?.completeWorkflowTask(id: taskID, result: result)
            } catch {
                await self?.failWorkflowTask(id: taskID, error: error)
            }
        }
    }

    private func completeWorkflowTask(id: UUID, result: Workflow.Result) {
        updateTask(id: id) { task in
            task.status = .done
            task.detail = "คลิป \(result.edit.storylineClipCount) · ซับ \(result.edit.captionCount) · " +
                String(format: "%.1f วินาที", result.edit.durationSeconds) +
                " · เพรเซ็ต \(result.exportPresetName)"
        }
        log("เวิร์กโฟลว์เสร็จ: " + result.steps.joined(separator: " → "))
    }

    private func failWorkflowTask(id: UUID, error: Error) {
        updateTask(id: id) { task in
            task.status = .failed
            task.detail = error.localizedDescription
        }
        log("เวิร์กโฟลว์ล้มเหลว: \(error.localizedDescription)")
    }

    private func updateTask(id: UUID, _ mutate: (inout StudioTask) -> Void) {
        guard let index = tasks.firstIndex(where: { $0.id == id }) else { return }
        mutate(&tasks[index])
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
