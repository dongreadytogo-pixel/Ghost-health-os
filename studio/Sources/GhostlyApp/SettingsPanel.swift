#if canImport(SwiftUI)
import SwiftUI
import GhostlyViewModels

/// Settings panel (M2): AI provider API keys, stored in the macOS Keychain
/// only (never files/preferences per the Constitution). Ranking/validation/
/// masking live in the CI-tested `SettingsViewModel`; this view only draws.
/// Thai-first labels.
struct SettingsPanel: View {
    private let model = SettingsViewModel(store: KeychainStore())
    @State private var rows: [SettingsViewModel.Row] = []
    @State private var drafts: [String: String] = [:]
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("การตั้งค่า").font(.title2.weight(.semibold))
            Text("คีย์ API เก็บไว้ใน Keychain ของเครื่องเท่านั้น ไม่บันทึกลงไฟล์")
                .font(.callout).foregroundStyle(.secondary)

            ForEach(rows, id: \.provider.id) { row in
                GroupBox(row.provider.name) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(row.statusLabel)
                            .font(.caption)
                            .foregroundStyle(row.hasKey ? .green : .secondary)
                        HStack {
                            SecureField(row.provider.hint,
                                        text: binding(for: row.provider.keychainKey))
                                .textFieldStyle(.roundedBorder)
                            Button("บันทึก") { save(row.provider) }
                                .disabled((drafts[row.provider.keychainKey] ?? "")
                                    .trimmingCharacters(in: .whitespaces).isEmpty)
                            if row.hasKey {
                                Button("ลบ", role: .destructive) { remove(row.provider) }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(4)
                }
            }

            if let error {
                Text(error).font(.caption).foregroundStyle(.red)
            }
            Spacer()
        }
        .padding()
        .onAppear(perform: reload)
        .navigationSubtitle("การตั้งค่า")
    }

    private func binding(for key: String) -> Binding<String> {
        Binding(get: { drafts[key] ?? "" }, set: { drafts[key] = $0 })
    }

    private func reload() { rows = model.rows() }

    private func save(_ provider: AIProviderEntry) {
        do {
            try model.save(drafts[provider.keychainKey] ?? "", for: provider)
            drafts[provider.keychainKey] = ""
            error = nil
            reload()
        } catch let StudioError.invalidInput(_, reason) {
            error = reason
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func remove(_ provider: AIProviderEntry) {
        try? model.removeKey(for: provider)
        reload()
    }
}
#endif
