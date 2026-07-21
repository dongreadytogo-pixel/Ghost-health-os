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

    func testAudioCleanupIntent() throws {
        XCTAssertEqual(parser.parse("ลดเสียงรบกวน"), [.cleanAudio])
        XCTAssertEqual(parser.parse("ช่วยแก้เสียงฮัมหน่อย"), [.cleanAudio])
        XCTAssertEqual(parser.parse("clean up the audio"), [.cleanAudio])
        XCTAssertEqual(parser.parse("remove background noise"), [.cleanAudio])
        XCTAssertTrue(try Director().interpret("ลดเสียงรบกวน ทำเป็นติ๊กต๊อก").wantsAudioCleanup)
        XCTAssertFalse(try Director().interpret("ทำเป็นติ๊กต๊อก").wantsAudioCleanup)
    }

    func testEnglishVocabularyUnaffected() {
        XCTAssertEqual(parser.parse("create a tiktok with captions, remove silence"),
                       [.createDeliverable(.tiktok),
                        .generateCaptions(styleName: "TikTok"),
                        .removeSilence])
    }

    // MARK: Smart command — "คัตเสียง เน้นประโยคสำคัญ ไม่เกิน 3 นาที"

    func testSmartThaiCommandParsesAllThreeIntents() {
        let intents = parser.parse(
            "คัตเสียงคลิปนี้โดยเน้นประโยคสำคัญที่น่าสนใจ ความยาวเหลือไม่เกิน 3 นาที")
        XCTAssertTrue(intents.contains(.removeSilence), "คัตเสียง → removeSilence")
        XCTAssertTrue(intents.contains(.emphasizeHighlights))
        XCTAssertTrue(intents.contains(.limitDuration(seconds: 180)))
    }

    func testDurationLimitVocabulary() {
        XCTAssertEqual(parser.durationLimit(in: "ไม่เกิน 3 นาที"), 180)
        XCTAssertEqual(parser.durationLimit(in: "เหลือไม่เกิน 90 วินาที"), 90)
        XCTAssertEqual(parser.durationLimit(in: "ภายใน 1 ชั่วโมง"), 3600)
        XCTAssertEqual(parser.durationLimit(in: "ไม่เกินสิบนาที"), 600)
        XCTAssertEqual(parser.durationLimit(in: "under 2 minutes"), 120)
        XCTAssertEqual(parser.durationLimit(in: "no more than 45 seconds"), 45)
        XCTAssertEqual(parser.durationLimit(in: "ไม่เกิน 1.5 นาที"), 90)
        XCTAssertNil(parser.durationLimit(in: "ตัดช่วงเงียบออก"), "no cap mentioned")
        XCTAssertNil(parser.durationLimit(in: "3 นาที"), "a bare duration is not a cap")
    }

    func testCutAudioDoesNotCollideWithNoiseCleanup() {
        XCTAssertEqual(parser.parse("ตัดเสียงรบกวน"), [.cleanAudio])
        XCTAssertTrue(parser.parse("ตัดเสียงช่วงที่เงียบ").contains(.removeSilence))
    }

    func testTitleSubtitlesVocabulary() throws {
        XCTAssertTrue(parser.parse("ใส่ซับแบบ Title").contains(.titleSubtitles))
        XCTAssertTrue(parser.parse("ซับแบบไตเติ้ล").contains(.titleSubtitles))
        XCTAssertTrue(parser.parse("subtitles as titles please").contains(.titleSubtitles))
        XCTAssertFalse(parser.parse("ใส่ซับ").contains(.titleSubtitles),
                       "plain ใส่ซับ stays caption-only")
        let plan = try Director().interpret("ทำเป็นติ๊กต๊อก ใส่ซับแบบ Title")
        XCTAssertTrue(plan.profile.titleSubtitles)
        XCTAssertTrue(plan.wantsCaptions, "the Title layer still needs the transcript")
    }

    func testLimitDurationResolvesIntoProfile() throws {
        let plan = try Director().interpret(
            "คัตเสียงคลิปนี้โดยเน้นประโยคสำคัญที่น่าสนใจ ความยาวเหลือไม่เกิน 3 นาที")
        XCTAssertEqual(plan.profile.maxTotalDuration, 180)
        XCTAssertTrue(plan.profile.emphasizeHighlights)
        XCTAssertEqual(plan.profile.silenceRemoval, 1,
                       "a length cap implies full silence removal")
    }
}
