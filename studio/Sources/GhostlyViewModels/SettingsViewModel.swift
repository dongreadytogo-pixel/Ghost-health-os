import Foundation
import GhostlyCore

/// One configurable AI provider in the settings panel.
public struct AIProviderEntry: Sendable, Equatable, Identifiable {
    public let id: String
    /// Thai-first display name.
    public let name: String
    /// Keychain account the key is stored under.
    public let keychainKey: String
    /// Placeholder hint for the input field.
    public let hint: String

    public init(id: String, name: String, keychainKey: String, hint: String) {
        self.id = id
        self.name = name
        self.keychainKey = keychainKey
        self.hint = hint
    }
}

/// Settings logic (M2), UI-framework-free: provider rows with Thai status
/// labels and masked previews over any `SecretsStoring`. The Keychain is
/// the only persistent backend (Constitution) — this model never sees a
/// key after saving it beyond the masked suffix.
public struct SettingsViewModel: Sendable {
    public static let providers: [AIProviderEntry] = [
        AIProviderEntry(id: "anthropic", name: "Anthropic (Claude)",
                        keychainKey: "anthropic-api-key", hint: "sk-ant-…"),
        AIProviderEntry(id: "openai", name: "OpenAI / เข้ากันได้ (LM Studio, DeepSeek)",
                        keychainKey: "openai-api-key", hint: "sk-…"),
        AIProviderEntry(id: "gemini", name: "Google Gemini",
                        keychainKey: "gemini-api-key", hint: "AIza…"),
        AIProviderEntry(id: "ollama", name: "Ollama (โฮสต์ในเครื่อง)",
                        keychainKey: "ollama-host", hint: "http://localhost:11434"),
    ]

    public struct Row: Sendable, Equatable {
        public let provider: AIProviderEntry
        public let hasKey: Bool
        /// "ตั้งค่าแล้ว (…abcd)" or "ยังไม่ได้ตั้งค่า".
        public let statusLabel: String
    }

    private let store: any SecretsStoring

    public init(store: any SecretsStoring) {
        self.store = store
    }

    public func rows() -> [Row] {
        Self.providers.map { provider in
            let secret = (try? store.secret(for: provider.keychainKey)) ?? nil
            if let secret, !secret.isEmpty {
                return Row(provider: provider, hasKey: true,
                           statusLabel: "ตั้งค่าแล้ว (\(Self.masked(secret)))")
            }
            return Row(provider: provider, hasKey: false, statusLabel: "ยังไม่ได้ตั้งค่า")
        }
    }

    /// Saves after validation: trimmed, non-empty, no internal whitespace.
    public func save(_ value: String, for provider: AIProviderEntry) throws {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw StudioError.invalidInput(field: provider.id, reason: "คีย์ว่างเปล่า")
        }
        guard !trimmed.contains(where: \.isWhitespace) else {
            throw StudioError.invalidInput(field: provider.id,
                                           reason: "คีย์ต้องไม่มีช่องว่าง")
        }
        try store.setSecret(trimmed, for: provider.keychainKey)
    }

    public func removeKey(for provider: AIProviderEntry) throws {
        try store.deleteSecret(for: provider.keychainKey)
    }

    /// Masks all but the last four characters: "…abcd"; short secrets mask
    /// entirely.
    public static func masked(_ secret: String) -> String {
        guard secret.count > 4 else { return "••••" }
        return "••••" + secret.suffix(4)
    }
}
