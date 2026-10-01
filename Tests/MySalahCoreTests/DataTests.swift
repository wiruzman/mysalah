import XCTest
import MySalahCore

final class DataTests: XCTestCase {
    private func raw(_ date: String, fajr: String = "05:00") -> RawPrayerDay {
        RawPrayerDay(date: date, fajr: fajr, sunrise: "07:00", dhuhr: "13:00", asr: "16:00", maghrib: "18:00", isha: "20:00")
    }
    func testCopenhagenDSTAndIstanbulOffset() throws {
        let cph = TimeZone(identifier: "Europe/Copenhagen")!, ist = TimeZone(identifier: "Europe/Istanbul")!
        let springBefore = try raw("28.03.2026").parsed(in: cph), springAfter = try raw("29.03.2026").parsed(in: cph)
        XCTAssertEqual(springAfter[.fajr]!.timeIntervalSince(springBefore[.fajr]!), 23 * 3600)
        let fallBefore = try raw("24.10.2026").parsed(in: cph), fallAfter = try raw("25.10.2026").parsed(in: cph)
        XCTAssertEqual(fallAfter[.fajr]!.timeIntervalSince(fallBefore[.fajr]!), 25 * 3600)
        let turkey = try raw("29.03.2026").parsed(in: ist)
        XCTAssertEqual(turkey[.fajr]!.timeIntervalSince(springAfter[.fajr]!), -3600)
    }
    func testNonexistentDSTClockIsRejected() {
        XCTAssertThrowsError(try raw("29.03.2026", fajr: "02:30").parsed(in: TimeZone(identifier: "Europe/Copenhagen")!))
    }
    func testSelectedTimezoneOverridesDeviceAndProviderMetadata() throws {
        let data = Data("""
        {"MiladiTarihKisa":"28.09.2026","MiladiTarihUzunIso8601":"2026-09-28T00:00:00+03:00","GreenwichOrtalamaZamani":3,"Imsak":"05:00","Gunes":"07:00","Ogle":"13:00","Ikindi":"16:00","Aksam":"18:00","Yatsi":"20:00"}
        """.utf8)
        let decoded = try JSONDecoder().decode(RawPrayerDay.self, from: data)
        let cph = try decoded.parsed(in: TimeZone(identifier: "Europe/Copenhagen")!)
        let ny = try decoded.parsed(in: TimeZone(identifier: "America/New_York")!)
        XCTAssertEqual(ny[.fajr]!.timeIntervalSince(cph[.fajr]!), 6 * 3600)
    }
    func testMalformedDateTimeAndOrderAreRejected() {
        let zone = TimeZone(identifier: "Europe/Copenhagen")!
        for date in ["31.02.2026", "2026-09-28", "", "01.13.2026"] { XCTAssertThrowsError(try raw(date).parsed(in: zone)) }
        for value in ["25:01", "05:60", "05:00:00", "bad", "17:00"] { XCTAssertThrowsError(try raw("28.09.2026", fajr: value).parsed(in: zone)) }
    }
    func testLiveCapturedFixturesDecode() throws {
        for (name, zone, expectedFajr) in [("copenhagen", "Europe/Copenhagen", "05:01"), ("istanbul", "Europe/Istanbul", "05:26")] {
            #if SWIFT_PACKAGE
            let bundle = Bundle.module
            #else
            let bundle = Bundle(for: Self.self)
            #endif
            let url = try XCTUnwrap(bundle.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"))
            let records = try JSONDecoder().decode([RawPrayerDay].self, from: Data(contentsOf: url))
            XCTAssertEqual(records.count, 3)
            let timezone = TimeZone(identifier: zone)!
            let days = try records.map { try $0.parsed(in: timezone) }
            XCTAssertEqual(TimeDisplay.clock(days[1][.fajr]!, format: .twentyFour, language: .en, timeZone: timezone), expectedFajr)
            XCTAssertEqual(days[1].times.count, 6)
        }
    }
    func testCacheRoundTripCorruptionAndFreshness() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = DiskCache(directory: directory), now = Date()
        let record = CachedTimetable(fetchedAt: now, days: [raw("28.09.2026")])
        try await cache.write(record, key: "times-26-685-12618")
        let loaded = await cache.read(CachedTimetable.self, key: "times-26-685-12618")
        XCTAssertEqual(loaded?.days, record.days)
        XCTAssertTrue(record.isFresh(at: now.addingTimeInterval(86_399)))
        XCTAssertFalse(record.isFresh(at: now.addingTimeInterval(86_400)))
        XCTAssertFalse(record.isFresh(at: now.addingTimeInterval(-1)))
        let file = try XCTUnwrap(FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).first)
        try Data("invalid".utf8).write(to: file)
        let broken = await cache.read(CachedTimetable.self, key: "times-26-685-12618")
        XCTAssertNil(broken)
    }
    func testLanguageResolutionAndTranslations() {
        XCTAssertEqual(AppLanguage.system.resolved(preferred: ["fr-FR", "da-DK"]), .da)
        XCTAssertEqual(AppLanguage.system.resolved(preferred: ["fr-FR"]), .en)
        XCTAssertEqual(AppLanguage.system.resolved(preferred: ["ar-SA"]), .ar)
        XCTAssertEqual(AppLanguage.tr.resolved(preferred: ["en-US"]), .tr)
        for lang in [AppLanguage.en, .da, .tr, .ar] {
            let strings = Localizer(language: lang)
            for prayer in Prayer.allCases { XCTAssertNotEqual(strings.name(prayer), "prayer.\(prayer.rawValue)") }
            XCTAssertNotEqual(strings.text("theme"), "theme")
            XCTAssertFalse(strings.text("notification.end.body", 15, strings.name(.asr)).contains("%@"))
            XCTAssertEqual(strings.isRTL, lang == .ar)
        }
    }
    @MainActor func testPreferencesPersistAndMixedReminders() throws {
        let name = UUID().uuidString
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let store = PreferencesStore(defaults: defaults)
        var settings = store.load()
        XCTAssertEqual(settings.theme, .system); XCTAssertEqual(settings.sharedReminder, 0)
        settings.setAllReminders(30); XCTAssertEqual(settings.sharedReminder, 30)
        settings.reminders[.asr] = 15; XCTAssertNil(settings.sharedReminder)
        settings.theme = .dark; settings.language = .ar; settings.developerMode = true; store.save(settings)
        XCTAssertEqual(store.load(), settings)
        XCTAssertEqual(settings.reminder(for: .sunrise), 0)
    }
    @MainActor func testLegacyPreferencesPreserveSettingsWithDeveloperModeOff() throws {
        let name = UUID().uuidString
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let store = PreferencesStore(defaults: defaults)
        XCTAssertFalse(store.load().developerMode)
        let legacy = Data("""
        {
          "theme":"dark", "language":"tr", "clockFormat":"twelve",
          "asrMethod":"hanafi", "startNotifications":false,
          "reminders":["asr",30],
          "location": {
            "locality": {
              "country":{"id":"26","name":"DANİMARKA","englishName":"DENMARK"},
              "region":{"id":"685","name":"DANİMARKA","englishName":"DENMARK"},
              "district":{"id":"12618","name":"KOPENHAG","englishName":"COPENHAGEN"}
            },
            "metadata":{"latitude":55.6761,"longitude":12.5683,"timeZoneIdentifier":"Europe/Copenhagen","label":"Copenhagen, Denmark"}
          }
        }
        """.utf8)
        defaults.set(legacy, forKey: "mysalah.preferences.v1")
        let preferences = store.load()
        XCTAssertFalse(preferences.developerMode)
        XCTAssertEqual(preferences.theme, .dark)
        XCTAssertEqual(preferences.language, .tr)
        XCTAssertEqual(preferences.clockFormat, .twelve)
        XCTAssertEqual(preferences.asrMethod, .hanafi)
        XCTAssertFalse(preferences.startNotifications)
        XCTAssertEqual(preferences.reminder(for: .asr), 30)
        XCTAssertEqual(preferences.location?.locality.id, "26-685-12618")
        XCTAssertEqual(preferences.location?.metadata.timeZoneIdentifier, "Europe/Copenhagen")
        store.save(preferences)
        XCTAssertEqual(store.load(), preferences)
    }
}
