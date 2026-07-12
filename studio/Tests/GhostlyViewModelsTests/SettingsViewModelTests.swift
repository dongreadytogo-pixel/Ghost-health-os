import XCTest
import GhostlyCore
@testable import GhostlyViewModels

/// Settings + secret storage (M2, Constitution: keys in Keychain only).
/// Tested against the in-memory store; the Keychain adapter shares the
/// `SecretsStoring` contract.
final class SettingsViewModelTests: XCTestCase {
    private func vm() -> (SettingsViewModel, InMemorySecretsStore) {
        let store = InMemorySecretsStore()
        return (SettingsViewModel(store: store), store)
    }

    func testAllProvidersStartUnconfigured() {
        let (model, _) = vm()
        let rows = model.rows()
        XCTAssertEqual(rows.count, 4)
        XCTAssertTrue(rows.allSatisfy { !$0.hasKey })
        XCTAssertTrue(rows.allSatisfy { $0.statusLabel == "ยังไม่ได้ตั้งค่า" })
    }

    func testSaveShowsMaskedStatus() throws {
        let (model, _) = vm()
        let anthropic = SettingsViewModel.providers[0]
        try model.save("sk-ant-secret1234", for: anthropic)
        let row = model.rows().first { $0.provider.id == "anthropic" }!
        XCTAssertTrue(row.hasKey)
        XCTAssertEqual(row.statusLabel, "ตั้งค่าแล้ว (••••1234)")
    }

    func testSaveIsPersistedToStoreOnly() throws {
        let (model, store) = vm()
        try model.save("sk-ant-abcd9999", for: SettingsViewModel.providers[0])
        XCTAssertEqual(try store.secret(for: "anthropic-api-key"), "sk-ant-abcd9999")
    }

    func testSaveTrimsAndValidates() {
        let (model, _) = vm()
        let p = SettingsViewModel.providers[0]
        XCTAssertThrowsError(try model.save("   ", for: p))
        XCTAssertThrowsError(try model.save("sk ant bad", for: p),
                             "keys with whitespace are rejected")
    }

    func testSaveTrimsSurroundingWhitespace() throws {
        let (model, store) = vm()
        try model.save("  sk-ant-trimmed  ", for: SettingsViewModel.providers[0])
        XCTAssertEqual(try store.secret(for: "anthropic-api-key"), "sk-ant-trimmed")
    }

    func testRemoveKey() throws {
        let (model, _) = vm()
        let p = SettingsViewModel.providers[1]
        try model.save("sk-openai-key1234", for: p)
        XCTAssertTrue(model.rows().first { $0.provider.id == "openai" }!.hasKey)
        try model.removeKey(for: p)
        XCTAssertFalse(model.rows().first { $0.provider.id == "openai" }!.hasKey)
    }

    func testMasking() {
        XCTAssertEqual(SettingsViewModel.masked("sk-ant-1234"), "••••1234")
        XCTAssertEqual(SettingsViewModel.masked("abc"), "••••", "short secrets fully masked")
        XCTAssertEqual(SettingsViewModel.masked("wxyz"), "••••")
    }
}
