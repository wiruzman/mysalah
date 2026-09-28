import XCTest
import MySalahCore

final class NotificationAndAsrTests: XCTestCase {
    let zone = TimeZone(identifier: "Europe/Copenhagen")!
    func day(_ date: String) throws -> PrayerDay {
        try RawPrayerDay(date: date, fajr: "05:00", sunrise: "07:00", dhuhr: "13:00", asr: "16:00", maghrib: "18:00", isha: "20:00").parsed(in: zone)
    }
    func testAllOffsetsUsePrayerEndIncludingFajrAndIsha() throws {
        let a = try day("28.09.2026"), b = try day("29.09.2026")
        for offset in [15, 30, 45] {
            var settings = Preferences(); settings.startNotifications = false; settings.setAllReminders(offset)
            let result = NotificationPlanner().plan(days: [a,b], preferences: settings, now: a.date, timeZone: zone)
            let fajr = try XCTUnwrap(result.first { $0.id.contains(".fajr.") })
            XCTAssertEqual(fajr.date, a[.sunrise]!.addingTimeInterval(-Double(offset * 60)))
            let isha = try XCTUnwrap(result.first { $0.id.contains(".isha.") })
            XCTAssertEqual(isha.date, b[.fajr]!.addingTimeInterval(-Double(offset * 60)))
            XCTAssertFalse(result.contains { $0.id.contains(".sunrise.") })
        }
    }
    func testIndividualSettingsAndNoPastEvents() throws {
        let a = try day("28.09.2026"), b = try day("29.09.2026")
        var settings = Preferences(); settings.startNotifications = false; settings.reminders[.asr] = 30
        let events = NotificationPlanner().plan(days: [a,b], preferences: settings, now: a[.asr]!, timeZone: zone)
        XCTAssertEqual(events.count, 2); XCTAssertTrue(events.allSatisfy { $0.id.contains(".asr.") })
        let after = NotificationPlanner().plan(days: [a], preferences: Preferences(), now: b.date, timeZone: zone)
        XCTAssertTrue(after.isEmpty)
    }
    func testSkipReminderBeforeStartAndLimitPendingRequests() throws {
        var a = try day("28.09.2026")
        a.times[.isha] = a[.maghrib]!.addingTimeInterval(10 * 60)
        var settings = Preferences(); settings.setAllReminders(45)
        let result = NotificationPlanner().plan(days: [a], preferences: settings, now: a.date, timeZone: zone)
        XCTAssertFalse(result.contains { $0.id.contains(".maghrib.") && $0.id.hasSuffix(".end") })
        let days = try (1...20).map { try day(String(format: "%02d.10.2026", $0)) }
        let all = NotificationPlanner().plan(days: days, preferences: settings, now: days[0].date, timeZone: zone)
        XCTAssertEqual(all.count, 60)
        XCTAssertEqual(Set(all.map(\.id)).count, all.count)
        XCTAssertEqual(all, all.sorted { $0.date < $1.date })
    }
    func testStableIDsAndLanguageRescheduling() throws {
        let a = try day("28.09.2026")
        let english = NotificationPlanner().plan(days: [a], preferences: Preferences(), now: a.date, timeZone: zone)
        var settings = Preferences(); settings.language = .tr
        let turkish = NotificationPlanner().plan(days: [a], preferences: settings, now: a.date, timeZone: zone)
        XCTAssertEqual(english.map(\.id), turkish.map(\.id)); XCTAssertNotEqual(english.first?.body, turkish.first?.body)
        let duplicate = NotificationPlanner().plan(days: [a,a], preferences: settings, now: a.date, timeZone: zone)
        XCTAssertEqual(duplicate.count, turkish.count)
    }
    func testKnownHanafiFixtureAndOnlyAsrChanges() throws {
        // Batoul Apps' published Raleigh fixture: 2015-07-12, Hanafi Asr ~18:22.
        // MySalah rounds up; the independent upstream fixture rounds to nearest.
        let metadata = LocationMetadata(latitude: 35.7750, longitude: -78.6336, timeZoneIdentifier: "America/New_York", label: "Raleigh")
        let original = try RawPrayerDay(date: "12.07.2015", fajr: "04:42", sunrise: "06:08", dhuhr: "13:21", asr: "17:00", maghrib: "20:32", isha: "21:57").parsed(in: metadata.timeZone!)
        let result = try XCTUnwrap(HanafiAsrCalculator().applying(to: [original], metadata: metadata).first)
        let clock = TimeDisplay.clock(try XCTUnwrap(result[.asr]), format: .twentyFour, language: .en, timeZone: metadata.timeZone!)
        XCTAssertTrue(["18:22", "18:23"].contains(clock), clock)
        for prayer in Prayer.allCases where prayer != .asr { XCTAssertEqual(result[prayer], original[prayer]) }
        XCTAssertEqual(ScheduleEngine().intervals(days: [result], timeZone: metadata.timeZone!).first(where: { $0.prayer == .dhuhr })?.end, result[.asr])
        var settings = Preferences(); settings.startNotifications = false; settings.reminders[.dhuhr] = 15
        let alerts = NotificationPlanner().plan(days: [result], preferences: settings, now: original.date, timeZone: metadata.timeZone!)
        XCTAssertEqual(alerts.first?.date, result[.asr]!.addingTimeInterval(-900))
    }
    func testInvalidHanafiNeverFallsBackToPublishedAsr() throws {
        let original = try day("28.09.2026")
        let invalid = LocationMetadata(latitude: 100, longitude: 12, timeZoneIdentifier: "Europe/Copenhagen", label: "Invalid")
        let result = HanafiAsrCalculator().applying(to: [original], metadata: invalid)[0]
        XCTAssertNil(result[.asr]); XCTAssertEqual(result[.dhuhr], original[.dhuhr])
        let intervals = ScheduleEngine().intervals(days: [result], timeZone: zone)
        XCTAssertFalse(intervals.contains { $0.prayer == .dhuhr || $0.prayer == .asr })
    }
}
