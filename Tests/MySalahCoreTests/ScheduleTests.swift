import XCTest
import MySalahCore

final class ScheduleTests: XCTestCase {
    let zone = TimeZone(identifier: "Europe/Copenhagen")!
    func day(_ date: String, isha: String = "20:00") throws -> PrayerDay {
        try RawPrayerDay(date: date, fajr: "05:00", sunrise: "07:00", dhuhr: "13:00", asr: "16:00", maghrib: "18:00", isha: isha).parsed(in: zone)
    }
    func testEachBoundaryAndSunriseGap() throws {
        let today = try day("28.09.2026"), tomorrow = try day("29.09.2026")
        let engine = ScheduleEngine()
        for prayer in Prayer.obligatory {
            let now = try XCTUnwrap(today[prayer])
            let result = engine.snapshot(days: [today, tomorrow], now: now, timeZone: zone)
            XCTAssertEqual(result.active?.prayer, prayer)
            XCTAssertEqual(result.rows.filter(\.isActive).count, 1)
            XCTAssertGreaterThan(try XCTUnwrap(result.nextBoundary), now)
        }
        let sunrise = try XCTUnwrap(today[.sunrise])
        XCTAssertEqual(engine.snapshot(days: [today, tomorrow], now: sunrise.addingTimeInterval(-1), timeZone: zone).active?.prayer, .fajr)
        let gap = engine.snapshot(days: [today, tomorrow], now: sunrise, timeZone: zone)
        XCTAssertNil(gap.active)
        XCTAssertEqual(gap.nextBoundary, today[.dhuhr])
        XCTAssertEqual(gap.nextPrayer, .dhuhr)
    }
    func testPreviousIshaAtMidnightAndBeforeDawn() throws {
        let yesterday = try day("27.09.2026"), today = try day("28.09.2026")
        for now in [today.date, today[.fajr]!.addingTimeInterval(-1)] {
            let result = ScheduleEngine().snapshot(days: [yesterday, today], now: now, timeZone: zone)
            XCTAssertEqual(result.active?.prayer, .isha)
            XCTAssertEqual(result.rows.last?.start, yesterday[.isha])
            XCTAssertEqual(result.rows.last?.isYesterday, true)
            XCTAssertEqual(result.nextBoundary, today[.fajr])
        }
        let after = ScheduleEngine().snapshot(days: [yesterday, today], now: today[.fajr]!, timeZone: zone)
        XCTAssertEqual(after.rows.last?.start, today[.isha])
        XCTAssertEqual(after.rows.last?.isYesterday, false)
    }
    func testMonthAndYearRollover() throws {
        for (first, second) in [("30.09.2026", "01.10.2026"), ("31.12.2026", "01.01.2027")] {
            let a = try day(first), b = try day(second)
            let result = ScheduleEngine().snapshot(days: [a,b], now: b.date, timeZone: zone)
            XCTAssertEqual(result.active?.start, a[.isha]); XCTAssertEqual(result.nextBoundary, b[.fajr])
        }
    }
    func testMissingTomorrowDoesNotInventIshaEnd() throws {
        let today = try day("28.09.2026"), distant = try day("30.09.2026")
        XCTAssertFalse(ScheduleEngine().intervals(days: [today, distant], timeZone: zone).contains { $0.prayer == .isha })
    }
    func testMissingTodayDoesNotReuseExpiredRows() throws {
        let yesterday = try day("27.09.2026"), today = try day("28.09.2026")
        let result = ScheduleEngine().snapshot(days: [yesterday], now: today[.dhuhr]!, timeZone: zone)
        XCTAssertFalse(result.hasToday); XCTAssertTrue(result.rows.allSatisfy { $0.start == nil })
        XCTAssertNil(result.active); XCTAssertNil(result.nextBoundary)
    }
    func testNorthernSummerIshaCrossesMidnight() throws {
        let today = try day("20.06.2026", isha: "00:20"), tomorrow = try day("21.06.2026")
        XCTAssertGreaterThan(today[.isha]!, tomorrow.date)
        let result = ScheduleEngine().snapshot(days: [today, tomorrow], now: today[.isha]!.addingTimeInterval(60), timeZone: zone)
        XCTAssertEqual(result.active?.prayer, .isha); XCTAssertTrue(result.rows.last!.isYesterday)
    }
    func testCountdownFormattingAndMinuteRounding() {
        let now = Date(timeIntervalSince1970: 0)
        for (seconds, expected) in [(3600.0, "01:00:00"), (3599, "59:59"), (60, "01:00"), (59, "00:59"), (0.1, "00:01"), (-1, "00:00")] {
            XCTAssertEqual(TimeDisplay.countdown(until: now.addingTimeInterval(seconds), now: now), expected)
        }
        XCTAssertEqual(TimeDisplay.minutes(until: now.addingTimeInterval(1), now: now), 1)
        XCTAssertEqual(TimeDisplay.minutes(until: now.addingTimeInterval(60), now: now), 1)
        XCTAssertEqual(TimeDisplay.minutes(until: now.addingTimeInterval(61), now: now), 2)
    }
    func testClockFormats() throws {
        let asr = try XCTUnwrap(day("28.09.2026")[.asr])
        XCTAssertEqual(TimeDisplay.clock(asr, format: .twentyFour, language: .en, timeZone: zone), "16:00")
        XCTAssertEqual(TimeDisplay.clock(asr, format: .twelve, language: .en, timeZone: zone), "4:00 PM")
    }
}
