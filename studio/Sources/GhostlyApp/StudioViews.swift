#if canImport(SwiftUI)
import SwiftUI
import GhostlySubtitles
import GhostlyDirector

/// Sidebar sections of the studio window.
enum StudioSection: String, CaseIterable, Identifiable {
    case director = "AI Director"
    case timeline = "ไทม์ไลน์"
    case assets = "คลังคลิป"
    case captions = "สไตล์คำบรรยาย"
    case queue = "คิวงาน"
    case logs = "บันทึกการทำงาน"
    case settings = "การตั้งค่า"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .director: return "wand.and.stars"
        case .timeline: return "film.stack"
        case .assets: return "photo.on.rectangle.angled"
        case .captions: return "captions.bubble"
        case .queue: return "list.bullet.rectangle"
        case .logs: return "terminal"
        case .settings: return "gearshape"
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
            case .assets: AssetBrowserPanel()
            case .captions: CaptionStylesPanel()
            case .queue: TaskQueuePanel(model: model)
            case .logs: LogsPanel(model: model)
            case .settings: SettingsPanel()
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
            Text("บอกสตูดิโอว่าอยากตัดต่อแบบไหน")
                .font(.title2.weight(.semibold))
            Text("ตัวอย่าง: “ตัดช่วงเงียบออก ทำเป็นติ๊กต๊อก ใส่ซับ” · “ลดเสียงรบกวน” · “Edit this like Marvel”")
                .font(.callout)
                .foregroundStyle(.secondary)

            HStack {
                TextField("คำสั่งตัดต่อ (ไทยหรืออังกฤษ)", text: $model.prompt)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { model.submitPrompt() }
                    .accessibilityLabel("คำสั่งตัดต่อ")
                Button("รัน") { model.submitPrompt() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(model.prompt.trimmingCharacters(in: .whitespaces).isEmpty)
            }

            if let plan = model.lastPlan {
                GroupBox("แผนล่าสุด") {
                    VStack(alignment: .leading, spacing: 6) {
                        LabeledContent("สไตล์", value: plan.profile.style.rawValue)
                        LabeledContent("ขนาดภาพ",
                            value: "\(plan.profile.format.width)×\(plan.profile.format.height)")
                        LabeledContent("ความยาวช็อต",
                            value: String(format: "%.1f–%.1f วินาที",
                                          plan.profile.minShotLength, plan.profile.maxShotLength))
                        LabeledContent("ตัดตามจังหวะ", value: plan.profile.cutOnBeats ? "ใช่" : "ไม่")
                        LabeledContent("คำบรรยาย", value: plan.profile.captionStyleName ?? "ไม่มี")
                        LabeledContent("ลดเสียงรบกวน", value: plan.wantsAudioCleanup ? "ใช่" : "ไม่")
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
        .navigationSubtitle("สไตล์คำบรรยาย")
    }
}

/// Live task queue.
struct TaskQueuePanel: View {
    @ObservedObject var model: StudioModel

    var body: some View {
        Group {
            if model.tasks.isEmpty {
                ContentUnavailableView("ยังไม่มีงาน",
                                       systemImage: "tray",
                                       description: Text("คำสั่งที่รันจะแสดงที่นี่"))
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
        .navigationSubtitle("คิวงาน")
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
        .navigationSubtitle("บันทึกการทำงาน")
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
