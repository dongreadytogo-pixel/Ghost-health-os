import XCTest
import GhostlyCore
@testable import GhostlyPlugin

final class PluginTests: XCTestCase {
    private func manifest(id: String = "com.example.retro",
                          version: String = "1.2.0",
                          minStudio: String = "1.0.0",
                          entryPoint: String = "Retro.bundle",
                          contributes: [ContributionKind] = [.captionStyles]) -> PluginManifest {
        PluginManifest(id: id, name: "Retro Pack",
                       version: SemanticVersion(version)!,
                       minStudioVersion: SemanticVersion(minStudio)!,
                       author: "Example Co", entryPoint: entryPoint,
                       permissions: [.filesystemRead], contributes: contributes)
    }

    // MARK: SemanticVersion

    func testSemverParsing() {
        XCTAssertEqual(SemanticVersion("1.2.3"), SemanticVersion(1, 2, 3))
        XCTAssertEqual(SemanticVersion("2"), SemanticVersion(2, 0, 0))
        XCTAssertEqual(SemanticVersion("2.1"), SemanticVersion(2, 1, 0))
        XCTAssertNil(SemanticVersion("1.2.3.4"))
        XCTAssertNil(SemanticVersion("1.x"))
        XCTAssertNil(SemanticVersion(""))
        XCTAssertNil(SemanticVersion("1..3"))
    }

    func testSemverOrdering() {
        XCTAssertLessThan(SemanticVersion(1, 9, 9), SemanticVersion(2, 0, 0))
        XCTAssertLessThan(SemanticVersion(1, 2, 3), SemanticVersion(1, 10, 0))
        XCTAssertGreaterThan(SemanticVersion(1, 0, 1), SemanticVersion(1, 0, 0))
    }

    func testSemverCodableAsString() throws {
        let data = try JSONEncoder().encode(SemanticVersion(1, 2, 3))
        XCTAssertEqual(String(data: data, encoding: .utf8), "\"1.2.3\"")
        XCTAssertEqual(try JSONDecoder().decode(SemanticVersion.self, from: data),
                       SemanticVersion(1, 2, 3))
    }

    // MARK: Manifest

    func testManifestParseFromJSON() throws {
        let json = """
        {"id":"com.example.retro-pack","name":"Retro Pack","version":"1.2.0",
         "minStudioVersion":"1.0.0","author":"Example Co","entryPoint":"RetroPack.bundle",
         "permissions":["filesystem.read","network"],"contributes":["captionStyles","mcpTools"]}
        """
        let m = try PluginManifest.parse(Data(json.utf8))
        XCTAssertEqual(m.id, "com.example.retro-pack")
        XCTAssertEqual(m.version, SemanticVersion(1, 2, 0))
        XCTAssertEqual(m.permissions, [.filesystemRead, .network])
        XCTAssertEqual(m.contributes, [.captionStyles, .mcpTools])
    }

    func testManifestParseRejectsMissingField() {
        let json = #"{"id":"com.example.x","name":"X"}"#
        XCTAssertThrowsError(try PluginManifest.parse(Data(json.utf8)))
    }

    func testManifestValidationRules() {
        XCTAssertThrowsError(try manifest(id: "notreversedns").validate())
        XCTAssertThrowsError(try manifest(id: "Com.Example.Upper").validate())
        XCTAssertThrowsError(try manifest(entryPoint: "../escape.bundle").validate())
        XCTAssertThrowsError(try manifest(entryPoint: "sub/dir.bundle").validate())
        XCTAssertThrowsError(try manifest(contributes: []).validate())
        XCTAssertNoThrow(try manifest().validate())
    }

    func testStudioCompatibility() {
        XCTAssertTrue(manifest(minStudio: "1.0.0")
            .isCompatible(withStudio: SemanticVersion(1, 0, 0)))
        XCTAssertFalse(manifest(minStudio: "2.0.0")
            .isCompatible(withStudio: SemanticVersion(1, 9, 9)))
    }

    // MARK: Lifecycle state machine

    func testLegalTransitionsTable() {
        XCTAssertTrue(PluginState.discovered.legalNextStates.contains(.validated))
        XCTAssertFalse(PluginState.discovered.legalNextStates.contains(.activated))
        XCTAssertTrue(PluginState.activated.legalNextStates.contains(.deactivated))
        XCTAssertTrue(PluginState.deactivated.legalNextStates.contains(.activated),
                      "hot reload requires re-activation")
        XCTAssertTrue(PluginState.unloaded.legalNextStates.isEmpty)
    }

    // MARK: Registry

    private func makeRegistry() -> PluginRegistry {
        PluginRegistry(studioVersion: SemanticVersion(1, 0, 0))
    }

    func testFullLifecycle() async throws {
        let registry = makeRegistry()
        let m = manifest()
        try await registry.discover(m)
        try await registry.validate(m.id)
        try await registry.load(m.id)
        try await registry.activate(m.id)
        var record = await registry.plugin(m.id)
        XCTAssertEqual(record?.state, .activated)

        // Hot reload: deactivate → activate.
        try await registry.deactivate(m.id)
        try await registry.activate(m.id)

        try await registry.deactivate(m.id)
        try await registry.unload(m.id)
        record = await registry.plugin(m.id)
        XCTAssertEqual(record?.state, .unloaded)
        try await registry.remove(m.id)
        let gone = await registry.plugin(m.id)
        XCTAssertNil(gone)
    }

    func testIllegalTransitionDoesNotCorruptState() async throws {
        let registry = makeRegistry()
        let m = manifest()
        try await registry.discover(m)
        // activate straight from discovered is illegal.
        do {
            try await registry.activate(m.id)
            XCTFail("expected illegal transition error")
        } catch { /* expected */ }
        let record = await registry.plugin(m.id)
        XCTAssertEqual(record?.state, .discovered, "state must be untouched")
    }

    func testDuplicateDiscoveryRejected() async throws {
        let registry = makeRegistry()
        try await registry.discover(manifest())
        do {
            try await registry.discover(manifest())
            XCTFail("expected duplicate rejection")
        } catch { /* expected */ }
    }

    func testValidationFailureMarksFailedWithReason() async throws {
        let registry = makeRegistry()
        let incompatible = manifest(id: "com.example.future", minStudio: "9.0.0")
        try await registry.discover(incompatible)
        do {
            try await registry.validate(incompatible.id)
            XCTFail("expected incompatibility error")
        } catch { /* expected */ }
        let record = await registry.plugin(incompatible.id)
        XCTAssertEqual(record?.state, .failed)
        XCTAssertTrue(record?.failureReason?.contains("9.0.0") ?? false)
        // Failed plugins can be removed for re-install.
        try await registry.remove(incompatible.id)
    }

    func testRemoveRequiresUnloadedOrFailed() async throws {
        let registry = makeRegistry()
        let m = manifest()
        try await registry.discover(m)
        do {
            try await registry.remove(m.id)
            XCTFail("expected refusal to remove a discovered plugin")
        } catch { /* expected */ }
    }

    func testContributorsFilterByKindAndActiveState() async throws {
        let registry = makeRegistry()
        let styles = manifest(id: "com.example.styles", contributes: [.captionStyles])
        let tools = manifest(id: "com.example.tools", contributes: [.mcpTools])
        for m in [styles, tools] {
            try await registry.discover(m)
            try await registry.validate(m.id)
            try await registry.load(m.id)
        }
        try await registry.activate(styles.id) // tools stays merely loaded

        let styleContributors = await registry.contributors(of: .captionStyles)
        let toolContributors = await registry.contributors(of: .mcpTools)
        XCTAssertEqual(styleContributors.map(\.id), ["com.example.styles"])
        XCTAssertTrue(toolContributors.isEmpty, "inactive plugins contribute nothing")
    }
}
