#if canImport(SwiftUI)
import SwiftUI
import GhostlySubtitles
import GhostlyDirector

/// Sidebar sections of the studio window.
enum StudioSection: String, CaseIterable, Identifiable {
    case director = "AI Director"
    case timeline = "ไทม์ไลน์"
    case captions = "Caption Styles"
    case queue = "Task Queue"
    case logs = "Logs"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .director: return "wand.and.stars"
        case .timeline: return "film.stack"
        case .captions: return "captions.bubble"
        case .queue: return "list.bullet.rectangle"
        case .logs: return "terminal"
        }
    }
}

public struct StudioRootView: View {
    @StateObject private var model = StudioModel()
    @State private var selection: StudioSection? = .director

    public init() {}

    public var body: some View {
        NavigationSplitView {
            List(StudioSection.allCases, selection: $selection) { section in
                Label(section.rawValue, systemImage: section.systemImage)
                    .tag(section)
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 210)
        } detail: {
            switch selection ?? .director {
            case .director: DirectorPanel(model: model)
            case .timeline: TimelineDemoPanel()
            case .captions: CaptionStylesPanel()
            case .queue: TaskQueuePanel(model: model)
            case .logs: LogsPanel(model: model)
            }
        }
        .navigationTitle("Ghostly Studio")
    }
}

/// Prompt panel: natural-language commands in, edit plans out.
struct DirectorPanel: View {
    @ObservedObject var model: StudioModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Tell the studio what to do")
                .font(.title2.weight(.semibold))
            Text("Examples: “Edit this like Marvel” · “Create a TikTok with captions” · “Make the pacing faster”")
                .font(.callout)
                .foregroundStyle(.secondary)

            HStack {
                TextField("Editing command", text: $model.prompt)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { model.submitPrompt() }
                    .accessibilityLabel("Editing command")
                Button("Run") { model.submitPrompt() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(model.prompt.trimmingCharacters(in: .whitespaces).isEmpty)
            }

            if let plan = model.lastPlan {
                GroupBox("Latest plan") {
                    VStack(alignment: .leading, spacing: 6) {
                        LabeledContent("Style", value: plan.profile.style.rawValue)
                        LabeledContent("Format",
                            value: "\(plan.profile.format.width)×\(plan.profile.format.height)")
                        LabeledContent("Shot length",
                            value: String(format: "%.1f–%.1f s",
                                          plan.profile.minShotLength, plan.profile.maxShotLength))
                        LabeledContent("Cut on beats", value: plan.profile.cutOnBeats ? "Yes" : "No")
                        LabeledContent("Captions", value: plan.profile.captionStyleName ?? "None")
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(4)
                }
            }
            Spacer()
        }
        .padding()
    }
}

/// Browsable caption style presets.
struct CaptionStylesPanel: View {
    var body: some View {
        List(CaptionStyle.builtIn, id: \.name) { style in
            VStack(alignment: .leading, spacing: 4) {
                Text(style.name).font(.headline)
                Text("\(style.fontName) · \(Int(style.fontSize)) pt · \(style.position.rawValue) · \(style.animation.rawValue)\(style.allCaps ? " · ALL CAPS" : "")")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
            .accessibilityElement(children: .combine)
        }
        .navigationSubtitle("Caption Styles")
    }
}

/// Live task queue.
struct TaskQueuePanel: View {
    @ObservedObject var model: StudioModel

    var body: some View {
        Group {
            if model.tasks.isEmpty {
                ContentUnavailableView("No tasks yet",
                                       systemImage: "tray",
                                       description: Text("Commands you run appear here."))
            } else {
                List(model.tasks) { task in
                    HStack(alignment: .top, spacing: 10) {
                        statusIcon(task.status)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(task.title).font(.body.weight(.medium))
                            if !task.detail.isEmpty {
                                Text(task.detail).font(.callout).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(.vertical, 2)
                    .accessibilityElement(children: .combine)
                }
            }
        }
        .navigationSubtitle("Task Queue")
    }

    @ViewBuilder
    private func statusIcon(_ status: StudioTask.Status) -> some View {
        switch status {
        case .queued: Image(systemName: "clock").foregroundStyle(.secondary)
        case .running: ProgressView().controlSize(.small)
        case .done: Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .failed: Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
        }
    }
}

/// Session log panel.
struct LogsPanel: View {
    @ObservedObject var model: StudioModel

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 2) {
                ForEach(Array(model.logEntries.enumerated()), id: \.offset) { _, entry in
                    Text(entry)
                        .font(.system(.callout, design: .monospaced))
                        .textSelection(.enabled)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
        }
        .navigationSubtitle("Logs")
    }
}

/// App entry point, used by the macOS application wrapper:
///
///     @main struct GhostlyStudioApp: App {
///         var body: some Scene { GhostlyStudioScene().body }
///     }
public struct GhostlyStudioScene {
    public init() {}

    public var body: some Scene {
        WindowGroup {
            StudioRootView()
                .frame(minWidth: 760, minHeight: 480)
        }
    }
}
#endif
