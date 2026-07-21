import Foundation
import GhostlyCore

/// Secret storage port (Constitution: API keys live in the Keychain only —
/// never in files or preferences). The Keychain adapter below is
/// platform-gated; tests and Linux use the in-memory store.
public protocol SecretsStoring: Sendable {
    func secret(for key: String) throws -> String?
    func setSecret(_ value: String, for key: String) throws
    func deleteSecret(for key: String) throws
}

/// Test/CI double: same contract, no persistence.
public final class InMemorySecretsStore: SecretsStoring, @unchecked Sendable {
    private var values: [String: String] = [:]
    private let lock = NSLock()

    public init() {}

    public func secret(for key: String) throws -> String? {
        lock.lock(); defer { lock.unlock() }
        return values[key]
    }

    public func setSecret(_ value: String, for key: String) throws {
        lock.lock(); defer { lock.unlock() }
        values[key] = value
    }

    public func deleteSecret(for key: String) throws {
        lock.lock(); defer { lock.unlock() }
        values[key] = nil
    }
}

#if canImport(Security)
import Security

/// macOS Keychain adapter: generic passwords under the studio's service
/// name, one account per provider key.
public struct KeychainStore: SecretsStoring {
    public var service: String

    public init(service: String = "com.ghostly790k.studio") {
        self.service = service
    }

    public func secret(for key: String) throws -> String? {
        var query = base(for: key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = item as? Data,
              let string = String(data: data, encoding: .utf8) else {
            throw StudioError.io(path: "keychain", detail: "read failed (status \(status))")
        }
        return string
    }

    public func setSecret(_ value: String, for key: String) throws {
        try? deleteSecret(for: key)
        var attributes = base(for: key)
        attributes[kSecValueData as String] = Data(value.utf8)
        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw StudioError.io(path: "keychain", detail: "write failed (status \(status))")
        }
    }

    public func deleteSecret(for key: String) throws {
        let status = SecItemDelete(base(for: key) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw StudioError.io(path: "keychain", detail: "delete failed (status \(status))")
        }
    }

    private func base(for key: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: key]
    }
}
#endif
