import XCTest
@testable import Pocket_Helper

@MainActor
final class MediaScanWindowTests: XCTestCase {
    func testTodayStartsAtLocalMidnight() throws {
        let calendar = utcCalendar()
        let reference = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026,
            month: 8,
            day: 15,
            hour: 18,
            minute: 30
        )))
        let cutoff = MediaScanWindow.today.cutoff(referenceDate: reference, calendar: calendar)
        let components = calendar.dateComponents([.year, .month, .day, .hour], from: cutoff)

        XCTAssertEqual(components.year, 2026)
        XCTAssertEqual(components.month, 8)
        XCTAssertEqual(components.day, 15)
        XCTAssertEqual(components.hour, 0)
    }

    func testRecentSevenDaysIncludesTodayAndPreviousSixCalendarDays() throws {
        let calendar = utcCalendar()
        let reference = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026,
            month: 8,
            day: 15,
            hour: 18,
            minute: 30
        )))
        let cutoff = MediaScanWindow.recentSevenDays.cutoff(referenceDate: reference, calendar: calendar)
        let components = calendar.dateComponents([.year, .month, .day, .hour], from: cutoff)

        XCTAssertEqual(components.year, 2026)
        XCTAssertEqual(components.month, 8)
        XCTAssertEqual(components.day, 9)
        XCTAssertEqual(components.hour, 0)
    }

    private func utcCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }
}
