import Foundation

/// Thai date and time formatting (Workflow Constitution v5): Buddhist-era
/// years, Thai month and weekday names, and the "น." time suffix — for
/// project names, metadata, notifications, and any user-facing Thai text.
/// Deterministic: pure Gregorian component math + hardcoded names, so no
/// ICU/locale data differences between platforms.
public enum ThaiDate {
    public static let monthNames = [
        "มกราคม", "กุมภาพันธ์", "มีนาคม", "เมษายน", "พฤษภาคม", "มิถุนายน",
        "กรกฎาคม", "สิงหาคม", "กันยายน", "ตุลาคม", "พฤศจิกายน", "ธันวาคม",
    ]
    public static let monthAbbreviations = [
        "ม.ค.", "ก.พ.", "มี.ค.", "เม.ย.", "พ.ค.", "มิ.ย.",
        "ก.ค.", "ส.ค.", "ก.ย.", "ต.ค.", "พ.ย.", "ธ.ค.",
    ]
    /// Indexed by Gregorian weekday (1 = Sunday … 7 = Saturday).
    public static let weekdayNames = [
        "วันอาทิตย์", "วันจันทร์", "วันอังคาร", "วันพุธ",
        "วันพฤหัสบดี", "วันศุกร์", "วันเสาร์",
    ]

    public enum Style: Sendable {
        /// "วันเสาร์ที่ 11 กรกฎาคม พ.ศ. 2569"
        case full
        /// "11 กรกฎาคม 2569"
        case long
        /// "11 ก.ค. 2569"
        case medium
        /// "11/07/2569"
        case short
    }

    /// Buddhist Era = Common Era + 543.
    public static func buddhistYear(fromGregorian year: Int) -> Int { year + 543 }

    public static let bangkok = TimeZone(identifier: "Asia/Bangkok")!

    public static func format(_ date: Date, style: Style = .long,
                              timeZone: TimeZone = bangkok) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.year, .month, .day, .weekday], from: date)
        guard let year = parts.year, let month = parts.month,
              let day = parts.day, let weekday = parts.weekday,
              (1...12).contains(month), (1...7).contains(weekday) else { return "" }
        let be = buddhistYear(fromGregorian: year)
        switch style {
        case .full:
            return "\(weekdayNames[weekday - 1])ที่ \(day) \(monthNames[month - 1]) พ.ศ. \(be)"
        case .long:
            return "\(day) \(monthNames[month - 1]) \(be)"
        case .medium:
            return "\(day) \(monthAbbreviations[month - 1]) \(be)"
        case .short:
            return String(format: "%02d/%02d/%d", day, month, be)
        }
    }

    /// Thai clock time, 24-hour with the "น." suffix: "14:30 น."
    public static func time(_ date: Date, timeZone: TimeZone = bangkok) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d น.", parts.hour ?? 0, parts.minute ?? 0)
    }

    /// Date + time for logs/notifications: "11 ก.ค. 2569 14:30 น."
    public static func timestamp(_ date: Date, timeZone: TimeZone = bangkok) -> String {
        "\(format(date, style: .medium, timeZone: timeZone)) \(time(date, timeZone: timeZone))"
    }
}
