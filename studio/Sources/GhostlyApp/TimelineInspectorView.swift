#if canImport(SwiftUI)
import SwiftUI
import GhostlyCore
import GhostlyDomain
import GhostlyViewModels

/// Timeline inspector (M2): a dumb renderer over `TimelineViewModel` —
/// every layout decision (lanes, normalized geometry, ruler, chips) is
/// computed and CI-tested in GhostlyViewModels; this view only draws.
/// User-facing text is Thai-first per the Workflow Constitution.
public struct TimelineInspectorView: View {
    public let model: TimelineViewModel

    public init(timeline: Timeline) {
        self.model = TimelineViewModel(timeline: timeline)
    }

    public init(model: TimelineViewModel) {
        self.model = model
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            GeometryReader { proxy in
                let width = proxy.size.width
                VStack(alignment: .leading, spacing: 6) {
                    ruler(width: width)
                    ForEach(model.lanes, id: \.index) { lane in
                        laneRow(lane, width: width)
                    }
                    if !model.captions.isEmpty {
                        captionRow(width: width)
                    }
                }
            }
        }
        .padding(12)
    }

    private var header: some View {
        HStack(spacing: 12) {
            Text(model.name).font(.headline)
            Text(String(format: "%.1f วินาที", model.durationSeconds))
                .font(.caption).foregroundStyle(.secondary)
            if model.isVertical {
                Text("แนวตั้ง 9:16").font(.caption2)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Capsule().fill(.quaternary))
            }
            Spacer()
            Text("ซับ \(model.captions.count) · มาร์กเกอร์ \(model.markers.count)")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func ruler(width: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            Rectangle().fill(.quaternary).frame(height: 18)
            ForEach(model.ticks, id: \.x) { tick in
                Text(tick.label)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .offset(x: width * tick.x, y: 2)
            }
            ForEach(model.markers, id: \.x) { marker in
                Image(systemName: "flag.fill")
                    .font(.system(size: 8))
                    .foregroundStyle(.orange)
                    .offset(x: width * marker.x, y: 4)
                    .help(marker.text)
            }
        }
        .frame(height: 18)
    }

    private func laneRow(_ lane: TimelineViewModel.Lane, width: CGFloat) -> some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 4).fill(.quaternary.opacity(0.5))
                .frame(height: 28)
            ForEach(lane.blocks) { block in
                RoundedRectangle(cornerRadius: 4)
                    .fill(color(forRole: block.roleName))
                    .frame(width: max(2, width * block.width), height: 28)
                    .overlay(alignment: .leading) {
                        HStack(spacing: 2) {
                            Text(block.name).font(.caption2).lineLimit(1)
                            if block.hasVolumeAutomation {
                                Image(systemName: "waveform.path")
                                    .font(.system(size: 8))
                            }
                        }
                        .padding(.leading, 4)
                        .foregroundStyle(.white)
                    }
                    .offset(x: width * block.x)
                    .help("\(block.name) — เลน \(lane.index)")
            }
        }
        .frame(height: 28)
    }

    private func captionRow(width: CGFloat) -> some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 3).fill(.quaternary.opacity(0.3))
                .frame(height: 16)
            ForEach(Array(model.captions.enumerated()), id: \.offset) { _, chip in
                RoundedRectangle(cornerRadius: 3)
                    .fill(.teal.opacity(0.7))
                    .frame(width: max(2, width * chip.width), height: 16)
                    .overlay(
                        Text(chip.speaker.map { "\($0): \(chip.text)" } ?? chip.text)
                            .font(.system(size: 8)).lineLimit(1)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 2)
                    )
                    .offset(x: width * chip.x)
                    .help(chip.text)
            }
        }
        .frame(height: 16)
    }

    private func color(forRole role: String) -> Color {
        switch role {
        case "music": return .purple.opacity(0.8)
        case "effects": return .orange.opacity(0.8)
        case "dialogue": return .green.opacity(0.8)
        default: return .blue.opacity(0.8)
        }
    }
}
#endif
