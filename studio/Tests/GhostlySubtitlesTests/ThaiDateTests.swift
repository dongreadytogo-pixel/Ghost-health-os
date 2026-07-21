import XCTest
@testable import GhostlySubtitles

/// Thai Buddhist-era date/time formatting (Workflow Constitution v5).
final class ThaiDateTests: XCTestCase {
    /// 2026-07-11 14:30 in Bangkok (a Saturday; BE 2569).
    private var saturdayAfternoon: Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = ThaiDate.bangkok
        return calendar.date(from: DateComponents(
            year: 2026, month: 7, day: 11, hour: 14, minute: 30))!
    }

    func testAllStyles() {
        let date = saturdayAfternoon
        XCTAssertEqual(ThaiDate.format(date, style: .full),
                       "วันเสาร์ที่ 11 กรกฎาคม พ.ศ. 2569")
        XCTAssertEqual(ThaiDate.format(date, style: .long), "11 กรกฎาคม 2569")
        XCTAssertEqual(ThaiDate.format(date, style: .medium), "11 ก.ค. 2569")
        XCTAssertEqual(ThaiDate.format(date, style: .short), "11/07/2569")
    }

    func testTimeAndTimestamp() {
        XCTAssertEqual(ThaiDate.time(saturdayAfternoon), "14:30 น.")
        XCTAssertEqual(ThaiDate.timestamp(saturdayAfternoon), "11 ก.ค. 2569 14:30 น.")
    }

    func testBuddhistEraMath() {
        XCTAssertEqual(ThaiDate.buddhistYear(fromGregorian: 2026), 2569)
        XCTAssertEqual(ThaiDate.buddhistYear(fromGregorian: 1957), 2500)
    }

    func testTimeZoneBoundary() {
        // 2026-07-10 23:00 UTC is already Saturday 06:00 in Bangkok.
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        let lateFriday = utc.date(from: DateComponents(
            year: 2026, month: 7, day: 10, hour: 23))!
        XCTAssertEqual(ThaiDate.format(lateFriday, style: .full),
                       "วันเสาร์ที่ 11 กรกฎาคม พ.ศ. 2569")
        XCTAssertEqual(ThaiDate.time(lateFriday), "06:00 น.")
        // And in UTC itself it is still Friday.
        XCTAssertEqual(ThaiDate.format(lateFriday, style: .full,
                                       timeZone: TimeZone(identifier: "UTC")!),
                       "วันศุกร์ที่ 10 กรกฎาคม พ.ศ. 2569")
    }

    func testLeapDay() {
        var bangkok = Calendar(identifier: .gregorian)
        bangkok.timeZone = ThaiDate.bangkok
        let leap = bangkok.date(from: DateComponents(year: 2024, month: 2, day: 29))!
        XCTAssertEqual(ThaiDate.format(leap, style: .full),
                       "วันพฤหัสบดีที่ 29 กุมภาพันธ์ พ.ศ. 2567")
    }
}
