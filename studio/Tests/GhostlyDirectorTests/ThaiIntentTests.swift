import XCTest
import GhostlyCore
import GhostlySubtitles
@testable import GhostlyDirector

/// Thai-first natural-language commands (Workflow Constitution v5): the
/// exact instruction styles a Thai editor types must parse into the same
/// intents as their English counterparts.
final class ThaiIntentTests: XCTestCase {
    private let parser = EditIntentParser()

    func testConstitutionExampleCommands() {
        XCTAssertEqual(parser.parse("ตัดช่วงเงียบออก"), [.removeSilence])
        XCTAssertEqual(parser.parse("ทำเป็นคลิป YouTube"),
                       [.createDeliverable(.youtube)])
        XCTAssertEqual(parser.parse("ทำเป็น Shorts"), [.createDeliverable(.shorts)])
        XCTAssertEqual(parser.parse("ใส่คำบรรยาย"),
                       [.generateCaptions(styleName: "Broadcast")])
        XCTAssertEqual(parser.parse("เร่งจังหวะ"), [.adjustPacing(direction: .faster)])
    }

    func testThaiDeliverablesWithThaiPlatformNames() {
        XCTAssertEqual(parser.parse("ทำเป็นติ๊กต๊อก"), [.createDeliverable(.tiktok)])
        XCTAssertEqual(parser.parse("ตัดเป็นคลิปยูทูบ"), [.createDeliverable(.youtube)])
        XCTAssertEqual(parser.parse("เอาไปลงไอจี"), [.createDeliverable(.instagram)])
        // Platform mention without a creation verb must not spawn one.
        XCTAssertEqual(parser.parse("ยูทูบ"), [])
    }

    func testThaiCaptionStyleDetection() {
        XCTAssertEqual(parser.parse("ใส่ซับสไตล์ติ๊กต๊อก").last,
                       .generateCaptions(styleName: "TikTok"))
        XCTAssertEqual(parser.parse("ใส่คำบรรยายแบบยูทูบ").last,
                       .generateCaptions(styleName: "YouTube"))
    }

    func testThaiCompoundCommand() {
        // One conversational sentence, several intents.
        let intents = parser.parse("ตัดช่วงเงียบออก ทำเป็นติ๊กต๊อก ใส่ซับ ตัดตามจังหวะเพลง")
        XCTAssertTrue(intents.contains(.removeSilence))
        XCTAssertTrue(intents.contains(.createDeliverable(.tiktok)))
        XCTAssertTrue(intents.contains(.cutToBeat))
        XCTAssertTrue(intents.contains { if case .generateCaptions = $0 { return true }; return false })
    }

    func testThaiStylesPacingMusicTransitions() {
        XCTAssertEqual(parser.parse("ปรับสีให้เหมือนหนัง แนวหนังเลย"),
                       [.applyStyle(.cinematic)])
        XCTAssertEqual(parser.parse("ตัดแนวสารคดี"), [.applyStyle(.documentary)])
        XCTAssertEqual(parser.parse("ช้าลงหน่อย"), [.adjustPacing(direction: .slower)])
        XCTAssertEqual(parser.parse("เปลี่ยนเพลงใหม่ให้หน่อย"), [.replaceMusic(query: nil)])
        XCTAssertEqual(parser.parse("ใส่ทรานสิชั่นระหว่างช็อต"),
                       [.addTransitions(name: "Cross Dissolve")])
        XCTAssertEqual(parser.parse("สไตล์ marvel"), [.applyStyle(.marvel)])
    }

    func testThaiCommandsDriveTheFullPipeline() throws {
        // The whole chain accepts conversational Thai end-to-end.
        let plan = try Director().interpret("ทำเป็นติ๊กต๊อก ตัดช่วงเงียบออก ใส่ซับ")
        XCTAssertTrue(plan.profile.format.isVertical)
        XCTAssertEqual(plan.profile.silenceRemoval, 1)
        XCTAssertTrue(plan.wantsCaptions)

        let srt = """
        1
        00:00:01,000 --> 00:00:03,500
        สวัสดีครับวันนี้เราจะมารีวิวกล้องตัวใหม่
        """
        let output = try EditPipeline.run(EditPipeline.Input(
            subtitles: srt, durationSeconds: 5,
            command: "ทำเป็นติ๊กต๊อก ตัดช่วงเงียบออก ใส่ซับ"))
        XCTAssertTrue(output.isValid, "issues: \(output.issues)")
        XCTAssertTrue(output.isVertical)
        XCTAssertTrue(output.fcpxml.contains("captionFormat=ITT.th"))
    }

    func testEnglishVocabularyUnaffected() {
        XCTAssertEqual(parser.parse("create a tiktok with captions, remove silence"),
                       [.createDeliverable(.tiktok),
                        .generateCaptions(styleName: "TikTok"),
                        .removeSilence])
    }
}
