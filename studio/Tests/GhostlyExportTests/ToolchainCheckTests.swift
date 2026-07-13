import XCTest
@testable import GhostlyExport

/// First-run readiness report (`ghostly doctor`): Thai output, honest about
/// what's installed and what the engine still does without the extras.
final class ToolchainCheckTests: XCTestCase {
    func testBothToolsPresentIsFullyEquipped() {
        let report = ToolchainCheck.report(found: ["ffmpeg": true, "whisper-cli": true])
        XCTAssertTrue(report.coreReady)
        XCTAssertTrue(report.fullyEquipped)
        XCTAssertTrue(report.lines.contains { $0.contains("พร้อมใช้งานเต็มรูปแบบ") })
        // Every tool line marked present.
        XCTAssertEqual(report.lines.filter { $0.contains("✓ ") }.count, 2)
    }

    func testMissingToolShowsInstallHintButCoreStillReady() {
        let report = ToolchainCheck.report(found: ["ffmpeg": false, "whisper-cli": true])
        // Both tools are optional, so the core is always ready.
        XCTAssertTrue(report.coreReady)
        XCTAssertFalse(report.fullyEquipped)
        XCTAssertTrue(report.lines.contains { $0.contains("✗ ffmpeg") })
        XCTAssertTrue(report.lines.contains { $0.contains("brew install ffmpeg") })
        XCTAssertTrue(report.lines.contains { $0.contains("เอนจินหลัก") },
                      "must reassure that editing works without the missing tool")
    }

    func testNothingInstalledStillReportsCoreUsable() {
        let report = ToolchainCheck.report(found: [:])
        XCTAssertTrue(report.coreReady, "the pure engine needs no external tools")
        XCTAssertFalse(report.fullyEquipped)
        // Both install hints present.
        XCTAssertTrue(report.lines.contains { $0.contains("whisper.cpp") })
        XCTAssertTrue(report.lines.contains { $0.contains("ffmpeg") })
    }

    func testToolsAreThaiDocumented() {
        for tool in ToolchainCheck.tools {
            XCTAssertFalse(tool.purpose.isEmpty)
            XCTAssertFalse(tool.installHint.isEmpty)
            // Purpose is written in Thai (contains Thai script).
            XCTAssertTrue(tool.purpose.unicodeScalars.contains { (0x0E00...0x0E7F).contains($0.value) })
        }
    }
}
