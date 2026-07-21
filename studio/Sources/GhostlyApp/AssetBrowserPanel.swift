#if canImport(SwiftUI)
import SwiftUI
import GhostlyCore
import GhostlyDomain
import GhostlyViewModels

/// Asset browser (M2): Thai natural-language search over the library.
/// Ranking/labels live in the CI-tested `AssetBrowserViewModel`; this view
/// only draws. Ships with a demo library until project loading arrives.
struct AssetBrowserPanel: View {
    @State private var query = ""

    private static let demoLibrary: [Asset] = [
        demo("สัมภาษณ์ช่างภาพ", tags: ["interview", "people"], seconds: 245, favorite: true),
        demo("แมวส้มบนหลังคา", tags: ["cat", "cute"], seconds: 32),
        demo("ทะเลตอนเย็น", tags: ["beach", "sunset", "sea"], seconds: 58),
        demo("โดรนภูเขาเชียงใหม่", tags: ["drone", "mountain", "nature"], seconds: 91),
        demo("บรรยากาศตลาดกลางคืน", tags: ["city", "night", "food"], seconds: 47),
        demo("เพลงประกอบสบาย ๆ", kind: .audio, tags: ["music"], seconds: 180),
    ]

    private static func demo(_ name: String, kind: Asset.Kind = .video,
                             tags: Set<String>, seconds: Double,
                             favorite: Bool = false) -> Asset {
        Asset(name: name, url: URL(fileURLWithPath: "/media/\(name)"),
              duration: RationalTime(seconds: seconds), kind: kind,
              format: kind == .video ? .hd1080p30 : nil,
              tags: tags, favorite: favorite)
    }

    private var model: AssetBrowserViewModel {
        AssetBrowserViewModel(assets: Self.demoLibrary, query: query)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("คลังคลิป").font(.title2.weight(.semibold))
            TextField("ค้นหา — เช่น แมว · ทะเล · คลิปกลางคืน · เสียงเพลง", text: $query)
                .textFieldStyle(.roundedBorder)
                .accessibilityLabel("ค้นหาคลิป")
            Text(model.summary).font(.caption).foregroundStyle(.secondary)

            List(model.rows) { row in
                HStack(spacing: 8) {
                    Image(systemName: row.kindLabel == "เสียง" ? "waveform"
                          : row.kindLabel == "รูปภาพ" ? "photo" : "film")
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 4) {
                            Text(row.name).font(.body)
                            if row.isFavorite {
                                Image(systemName: "star.fill")
                                    .font(.caption2).foregroundStyle(.yellow)
                            }
                        }
                        Text("\(row.kindLabel) · \(row.durationLabel)"
                             + (row.tags.isEmpty ? "" : " · \(row.tags.joined(separator: ", "))"))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                }
            }
            .listStyle(.inset)
        }
        .padding()
    }
}
#endif
