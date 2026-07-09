import XCTest
import GhostlyCore
@testable import GhostlySubtitles

final class ThaiNumberTests: XCTestCase {
    // MARK: spell(_:)

    func testBasicNumbers() {
        XCTAssertEqual(ThaiNumber.spell(0), "ศูนย์")
        XCTAssertEqual(ThaiNumber.spell(1), "หนึ่ง")
        XCTAssertEqual(ThaiNumber.spell(5), "ห้า")
        XCTAssertEqual(ThaiNumber.spell(10), "สิบ")
        XCTAssertEqual(ThaiNumber.spell(11), "สิบเอ็ด")
        XCTAssertEqual(ThaiNumber.spell(20), "ยี่สิบ")
        XCTAssertEqual(ThaiNumber.spell(21), "ยี่สิบเอ็ด")
        XCTAssertEqual(ThaiNumber.spell(99), "เก้าสิบเก้า")
    }

    func testHundredsAndAbove() {
        XCTAssertEqual(ThaiNumber.spell(100), "หนึ่งร้อย")
        XCTAssertEqual(ThaiNumber.spell(150), "หนึ่งร้อยห้าสิบ")
        XCTAssertEqual(ThaiNumber.spell(101), "หนึ่งร้อยเอ็ด")
        XCTAssertEqual(ThaiNumber.spell(1_000), "หนึ่งพัน")
        XCTAssertEqual(ThaiNumber.spell(2_567), "สองพันห้าร้อยหกสิบเจ็ด")
        XCTAssertEqual(ThaiNumber.spell(10_000), "หนึ่งหมื่น")
        XCTAssertEqual(ThaiNumber.spell(100_000), "หนึ่งแสน")
    }

    func testMillions() {
        XCTAssertEqual(ThaiNumber.spell(1_000_000), "หนึ่งล้าน")
        XCTAssertEqual(ThaiNumber.spell(2_500_000), "สองล้านห้าแสน")
        XCTAssertEqual(ThaiNumber.spell(1_000_000_000), "หนึ่งพันล้าน")
    }

    func testNegative() {
        XCTAssertEqual(ThaiNumber.spell(-21), "ลบยี่สิบเอ็ด")
    }

    // MARK: verbalize(_:)

    func testVerbalizeReplacesNumbersInText() {
        XCTAssertEqual(ThaiNumber.verbalize("ราคา 150 บาท"),
                       "ราคา หนึ่งร้อยห้าสิบ บาท")
        XCTAssertEqual(ThaiNumber.verbalize("ตอนที่ 21"), "ตอนที่ ยี่สิบเอ็ด")
    }

    func testVerbalizeThaiDigits() {
        XCTAssertEqual(ThaiNumber.verbalize("ราคา ๑๕๐ บาท"),
                       "ราคา หนึ่งร้อยห้าสิบ บาท")
    }

    func testVerbalizeDecimals() {
        XCTAssertEqual(ThaiNumber.verbalize("คะแนน 3.5 ดาว"),
                       "คะแนน สามจุดห้า ดาว")
    }

    func testVerbalizeLeavesTextWithoutNumbersUntouched() {
        let text = "สวัสดีครับ ยินดีต้อนรับ"
        XCTAssertEqual(ThaiNumber.verbalize(text), text)
    }

    // MARK: SubtitleTrack integration

    func testTrackVerbalization() {
        let track = SubtitleTrack(language: "th", cues: [
            SubtitleCue(range: TimeRange(start: RationalTime(seconds: 0),
                                         duration: RationalTime(seconds: 2)),
                        text: "ลด 50 เปอร์เซ็นต์"),
            SubtitleCue(range: TimeRange(start: RationalTime(seconds: 2),
                                         duration: RationalTime(seconds: 2)),
                        text: "ไม่มีตัวเลข"),
        ])
        let spoken = track.verbalizingThaiNumbers()
        XCTAssertEqual(spoken.cues[0].text, "ลด ห้าสิบ เปอร์เซ็นต์")
        XCTAssertEqual(spoken.cues[1].text, "ไม่มีตัวเลข", "cues without numbers are untouched")
        XCTAssertEqual(spoken.cues[0].range, track.cues[0].range, "timing preserved")
        XCTAssertEqual(spoken.language, "th")
    }
}
