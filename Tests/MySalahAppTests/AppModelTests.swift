import XCTest
import AppKit
import UserNotifications
import SwiftUI
import MySalahCore

private struct FixedClock: AppClock {
    let date: Date
    func now() -> Date { date }
}
private actor ControlledProvider: PrayerTimeProvider {
    var requests: [String: CheckedContinuation<[RawPrayerDay], Error>] = [:]
    func countries() async throws -> [Place] { [] }
    func regions(countryID: String) async throws -> [Place] { [] }
    func districts(regionID: String) async throws -> [Place] { [] }
    func timetable(districtID: String) async throws -> [RawPrayerDay] {
        try await withCheckedThrowingContinuation { requests[districtID] = $0 }
    }
    func hasRequest(_ id: String) -> Bool { requests[id] != nil }
    func complete(_ id: String, with result: Result<[RawPrayerDay], Error>) { requests.removeValue(forKey: id)?.resume(with: result) }
}
@MainActor private final class FixedResolver: LocationResolving {
    var matches: [LocationMetadata]
    init(matches: [LocationMetadata]) { self.matches = matches }
    func resolve(_ locality: Locality) async throws -> [LocationMetadata] { matches }
}
@MainActor private final class MockNotifications: NotificationManaging {
    var authorization: UNAuthorizationStatus = .denied
    var requests = 0
    var events: [PlannedNotification] = []
    func updateAuthorization(request: Bool) async { if request { requests += 1 } }
    func replace(with events: [PlannedNotification]) async throws { self.events = events }
}

@MainActor final class AppModelTests: XCTestCase {
    override func setUp() async throws {
        try await super.setUp()
        await MainActor.run {
            // Hostless XCTest does not run NSApplicationMain. Initialize AppKit
            // before status items or offscreen views need a WindowServer connection.
            _ = NSApplication.shared
        }
    }

    private var temporaryDirectories: [URL] = []
    private var suites: [String] = []
    let metadata = LocationMetadata(latitude: 55.6761, longitude: 12.5683, timeZoneIdentifier: "Europe/Copenhagen", label: "Copenhagen, Denmark")
    private func raw(_ date: String, asr: String = "16:09") -> RawPrayerDay {
        RawPrayerDay(date: date, fajr: "05:01", sunrise: "07:00", dhuhr: "13:06", asr: asr, maghrib: "18:30", isha: "20:00")
    }
    private func locality(_ id: String) -> Locality {
        Locality(country: Place(id: "26", name: "DANİMARKA", englishName: "DENMARK"), region: Place(id: "685", name: "DANİMARKA", englishName: "DENMARK"), district: Place(id: id, name: "KOPENHAG", englishName: "KOPENHAGEN"))
    }
    private func makeModel(provider: ControlledProvider, notifications: MockNotifications = MockNotifications(), selected: Bool = false, matches: [LocationMetadata]? = nil) throws -> (AppModel, DiskCache) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        temporaryDirectories.append(directory)
        let cache = DiskCache(directory: directory)
        let suite = UUID().uuidString; suites.append(suite)
        let store = PreferencesStore(defaults: UserDefaults(suiteName: suite)!)
        if selected {
            var settings = Preferences(); settings.location = SelectedLocation(locality: locality("12618"), metadata: metadata); store.save(settings)
        }
        let date = try raw("28.09.2026").parsed(in: metadata.timeZone!)[.asr]!.addingTimeInterval(60)
        return (AppModel(provider: provider, resolver: FixedResolver(matches: matches ?? [metadata]), cache: cache, store: store, notifications: notifications, clock: FixedClock(date: date)), cache)
    }
    override func tearDown() async throws {
        for directory in temporaryDirectories { try? FileManager.default.removeItem(at: directory) }
        for suite in suites { UserDefaults.standard.removePersistentDomain(forName: suite) }
        temporaryDirectories = []; suites = []
    }
    private func eventually(_ condition: @MainActor () async -> Bool) async throws {
        for _ in 0..<200 {
            if await condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Asynchronous operation did not finish within two seconds")
        throw URLError(.timedOut)
    }
    func testSlowOldLocationCannotReplaceNewLocation() async throws {
        let provider = ControlledProvider()
        let (model, _) = try makeModel(provider: provider)
        model.select(locality("old"))
        try await eventually { await provider.hasRequest("old") }
        model.select(locality("new"))
        try await eventually { await provider.hasRequest("new") }
        await provider.complete("new", with: .success([raw("28.09.2026", asr: "16:30"), raw("29.09.2026")]))
        try await eventually { !model.isLoading }
        await provider.complete("old", with: .success([raw("28.09.2026", asr: "15:30"), raw("29.09.2026")]))
        await Task.yield()
        XCTAssertEqual(model.preferences.location?.locality.district.id, "new")
        XCTAssertEqual(TimeDisplay.clock(model.days[0][.asr]!, format: .twentyFour, language: .en, timeZone: metadata.timeZone!), "16:30")
    }
    func testOfflineCacheAndDeniedPermission() async throws {
        let provider = ControlledProvider(), notifications = MockNotifications()
        let (model, cache) = try makeModel(provider: provider, notifications: notifications, selected: true)
        let record = CachedTimetable(fetchedAt: model.now.addingTimeInterval(-90_000), days: [raw("27.09.2026"),raw("28.09.2026"),raw("29.09.2026")])
        try await cache.write(record, key: "times-26-685-12618")
        model.refresh()
        try await eventually { await provider.hasRequest("12618") }
        await provider.complete("12618", with: .failure(URLError(.notConnectedToInternet)))
        try await eventually { !model.isLoading && model.notificationStatusKey == "notifications.denied" }
        XCTAssertTrue(model.usingCache); XCTAssertEqual(model.snapshot?.hasToday, true)
        XCTAssertEqual(model.failureKey, "status.offline"); XCTAssertEqual(notifications.requests, 0)
    }
    func testAmbiguousAndUnresolvedLocationsRequireUserChoice() async throws {
        let provider = ControlledProvider()
        let second = LocationMetadata(latitude: 56, longitude: 12, timeZoneIdentifier: "Europe/Copenhagen", label: "Another town")
        let (model, _) = try makeModel(provider: provider, matches: [metadata, second])
        model.select(locality("12618"))
        try await eventually { model.locationMatches.count == 2 }
        XCTAssertNil(model.preferences.location)
        model.chooseMatch(metadata)
        try await eventually { await provider.hasRequest("12618") }
        await provider.complete("12618", with: .success([raw("28.09.2026"),raw("29.09.2026")]))
        try await eventually { !model.isLoading }
        XCTAssertEqual(model.preferences.location?.metadata, metadata)
        let (failed, _) = try makeModel(provider: provider, matches: [])
        failed.select(locality("none"))
        try await eventually { failed.failureKey == "status.locationFailed" }
        XCTAssertNil(failed.preferences.location)
    }
    func testNativeMenusCheckmarksAndReminderOptions() throws {
        let (model, _) = try makeModel(provider: ControlledProvider())
        let controller = StatusMenuController(model: model)
        defer { controller.stop(); NSApp.appearance = nil }
        let strings = model.strings
        let theme = try XCTUnwrap(controller.menu.items.first { $0.title == strings.text("theme") }?.submenu)
        XCTAssertEqual(theme.items.map(\.state), [.on, .off, .off])
        let reminders = try XCTUnwrap(controller.menu.items.first { $0.title == strings.text("reminders") }?.submenu)
        XCTAssertEqual(reminders.items.filter { $0.submenu != nil }.count, 6)
        let all = try XCTUnwrap(reminders.items.first?.submenu)
        XCTAssertEqual(all.items.count, 4); XCTAssertEqual(all.items[0].state, .on)
        all.performActionForItem(at: 2)
        XCTAssertEqual(model.preferences.sharedReminder, 30)
        let language = try XCTUnwrap(controller.menu.items.first { $0.title == strings.text("language") }?.submenu)
        XCTAssertEqual(language.items.count, 5)
        let panel = try XCTUnwrap(controller.menu.items.first?.view)
        XCTAssertGreaterThan(panel.frame.height, 60)
    }
    func testPanelRendersAllLanguagesAndThemes() throws {
        let (model, _) = try makeModel(provider: ControlledProvider(), selected: true)
        model.days = try [raw("27.09.2026"),raw("28.09.2026"),raw("29.09.2026")].map { try $0.parsed(in: metadata.timeZone!) }
        model.fetchedAt = model.now
        let output: URL? = ProcessInfo.processInfo.environment["MYSALAH_PREVIEW_DIR"].map { URL(fileURLWithPath: $0) }
            ?? URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("build/previews")
        if let output { try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true) }
        for language in [AppLanguage.en, .da, .tr, .ar] {
            for theme in [Theme.light, .dark] {
                model.preferences.language = language; model.preferences.theme = theme
                let view = NSHostingView(rootView: PrayerPanel(model: model).background(Color(nsColor: .windowBackgroundColor)).environment(\.colorScheme, theme == .dark ? .dark : .light))
                view.appearance = NSAppearance(named: theme == .dark ? .darkAqua : .aqua)
                view.frame = NSRect(origin: .zero, size: view.fittingSize)
                view.layoutSubtreeIfNeeded()
                XCTAssertEqual(view.frame.width, 368, accuracy: 1)
                XCTAssertGreaterThan(view.frame.height, 300); XCTAssertLessThan(view.frame.height, 600)
                if let output, let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
                    view.cacheDisplay(in: view.bounds, to: bitmap)
                    let data = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
                    try data.write(to: output.appendingPathComponent("\(language.rawValue)-\(theme.rawValue).png"))
                }
            }
        }
    }
    func testLiveServicesWhenExplicitlyEnabled() async throws {
        guard ProcessInfo.processInfo.environment["MYSALAH_LIVE_TESTS"] == "1" else { throw XCTSkip("Run MYSALAH_LIVE_TESTS=1 ./scripts/test-app.sh to enable live service checks") }
        let provider = EzanVaktiProvider()
        let countries = try await provider.countries()
        let country = try XCTUnwrap(countries.first { $0.id == "26" })
        let regions = try await provider.regions(countryID: country.id)
        let region = try XCTUnwrap(regions.first { $0.id == "685" })
        let districts = try await provider.districts(regionID: region.id)
        let district = try XCTUnwrap(districts.first { $0.id == "12618" })
        let locality = Locality(country: country, region: region, district: district)
        let matches = try await AppleLocationResolver().resolve(locality)
        XCTAssertEqual(matches.count, 1)
        XCTAssertEqual(matches.first?.timeZoneIdentifier, "Europe/Copenhagen")
        let rows = try await provider.timetable(districtID: district.id)
        let parsed = try rows.map { try $0.parsed(in: metadata.timeZone!) }
        XCTAssertTrue(parsed.contains { Calendar.current.isDateInToday($0.date) })
        let turkish = try await provider.timetable(districtID: "9541")
        XCTAssertFalse(turkish.isEmpty)
        _ = try turkish.map { try $0.parsed(in: TimeZone(identifier: "Europe/Istanbul")!) }
    }
}
