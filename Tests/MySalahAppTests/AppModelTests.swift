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
    var replacementCount = 0
    var tests: [(prayer: Prayer, kind: NotificationTestKind, language: AppLanguage)] = []
    var nextAuthorization: UNAuthorizationStatus?
    var testFailure: Error?
    var suspendTests = false
    var testWaiters: [CheckedContinuation<Void, Error>] = []
    var completedTests = 0
    var suspendAuthorization = false
    var authorizationWaiter: CheckedContinuation<Void, Never>?
    var completedAuthorizations = 0
    func updateAuthorization(request: Bool) async {
        if suspendAuthorization {
            await withCheckedContinuation { authorizationWaiter = $0 }
        }
        completedAuthorizations += 1
        if request { requests += 1 }
        if let nextAuthorization { authorization = nextAuthorization }
    }
    func replace(with events: [PlannedNotification]) async throws { self.events = events; replacementCount += 1 }
    func sendTest(prayer: Prayer, kind: NotificationTestKind, language: AppLanguage) async throws {
        defer { completedTests += 1 }
        if suspendTests {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in testWaiters.append(continuation) }
        }
        if let testFailure { throw testFailure }
        tests.append((prayer, kind, language))
    }
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
    func testDeveloperModeControlsTestMenuAndPersistsWithoutRescheduling() throws {
        let notifications = MockNotifications(); notifications.authorization = .authorized
        let (model, _) = try makeModel(provider: ControlledProvider(), notifications: notifications)
        let store = PreferencesStore(defaults: UserDefaults(suiteName: try XCTUnwrap(suites.last))!)
        for language in [AppLanguage.en, .da, .tr, .ar] {
            model.preferences.language = language
            XCTAssertFalse(model.preferences.developerMode)
            XCTAssertFalse(model.canSendTestNotification)
            let controller = StatusMenuController(model: model)
            defer { controller.stop(); NSApp.appearance = nil }
            let developerTitle = model.strings.text("developerMode")
            let testTitle = model.strings.text("notifications.test")
            XCTAssertNotEqual(developerTitle, "developerMode")
            XCTAssertFalse(controller.menu.items.contains { $0.title == testTitle })
            let developer = try XCTUnwrap(controller.menu.items.first { $0.title == developerTitle }?.submenu)
            XCTAssertEqual(developer.items.map(\.state), [.off, .on])
            developer.performActionForItem(at: 0)
            XCTAssertTrue(model.canSendTestNotification)
            XCTAssertTrue(store.load().developerMode)
            XCTAssertTrue(controller.menu.items.contains { $0.title == testTitle })
            let enabled = try XCTUnwrap(controller.menu.items.first { $0.title == developerTitle }?.submenu)
            XCTAssertEqual(enabled.items.map(\.state), [.on, .off])
            enabled.performActionForItem(at: 1)
            XCTAssertFalse(store.load().developerMode)
            XCTAssertFalse(controller.menu.items.contains { $0.title == testTitle })
            model.sendTestNotification(prayer: .fajr, kind: .start)
        }
        XCTAssertTrue(notifications.tests.isEmpty)
        XCTAssertEqual(notifications.completedAuthorizations, 0)
        XCTAssertEqual(notifications.requests, 0)
        XCTAssertEqual(notifications.replacementCount, 0)
    }
    func testDisablingDeveloperModeCancelsTestAwaitingAuthorization() async throws {
        let notifications = MockNotifications(); notifications.authorization = .authorized; notifications.suspendAuthorization = true
        let (model, _) = try makeModel(provider: ControlledProvider(), notifications: notifications)
        model.setDeveloperMode(true)
        model.sendTestNotification(prayer: .fajr, kind: .start)
        try await eventually { notifications.authorizationWaiter != nil }
        model.setDeveloperMode(false)
        notifications.authorizationWaiter?.resume()
        try await eventually { notifications.completedAuthorizations == 1 }
        XCTAssertTrue(notifications.tests.isEmpty)
        XCTAssertFalse(model.canSendTestNotification)
        XCTAssertNil(model.notificationTestFailureKey)
        XCTAssertEqual(notifications.requests, 0)
        XCTAssertEqual(notifications.replacementCount, 0)
    }
    func testNotificationMenuSendsEveryVariantWithoutChangingPreferencesOrSchedule() async throws {
        let notifications = MockNotifications(); notifications.authorization = .authorized
        let (model, _) = try makeModel(provider: ControlledProvider(), notifications: notifications)
        model.setDeveloperMode(true)
        model.preferences.startNotifications = false
        var sent = 0
        for language in [AppLanguage.en, .da, .tr, .ar] {
            model.preferences.language = language
            let preferences = model.preferences
            let controller = StatusMenuController(model: model)
            defer { controller.stop(); NSApp.appearance = nil }
            let menu = try XCTUnwrap(controller.menu.items.first { $0.title == model.strings.text("notifications.test") }?.submenu)
            let prayers = menu.items.compactMap(\.submenu)
            XCTAssertEqual(prayers.map(\.title), Prayer.obligatory.map { model.strings.name($0) })
            for (prayer, child) in zip(Prayer.obligatory, prayers) {
                XCTAssertEqual(child.items.count, 4)
                for (index, kind) in NotificationTestKind.allCases.enumerated() {
                    XCTAssertTrue(child.items[index].isEnabled)
                    XCTAssertEqual(child.items[index].title, kind.title(using: model.strings))
                    child.performActionForItem(at: index)
                    sent += 1
                    try await eventually { notifications.tests.count == sent }
                    XCTAssertEqual(notifications.tests.last?.prayer, prayer)
                    XCTAssertEqual(notifications.tests.last?.kind, kind)
                    XCTAssertEqual(notifications.tests.last?.language, language)
                }
            }
            XCTAssertEqual(model.preferences, preferences)
        }
        XCTAssertEqual(notifications.requests, 0)
        XCTAssertEqual(notifications.replacementCount, 0)
    }
    func testNotificationTestsDoNotRequestPermissionAndRecheckRevokedPermission() async throws {
        let notifications = MockNotifications()
        let (model, _) = try makeModel(provider: ControlledProvider(), notifications: notifications)
        model.setDeveloperMode(true)
        for status in [UNAuthorizationStatus.denied, .notDetermined] {
            notifications.authorization = status
            let controller = StatusMenuController(model: model)
            defer { controller.stop(); NSApp.appearance = nil }
            let menu = try XCTUnwrap(controller.menu.items.first { $0.title == model.strings.text("notifications.test") }?.submenu)
            XCTAssertTrue(menu.items.contains { $0.title == model.strings.text("notifications.settings") })
            XCTAssertTrue(menu.items.compactMap(\.submenu).flatMap(\.items).allSatisfy { !$0.isEnabled })
        }
        notifications.authorization = .authorized
        notifications.nextAuthorization = .denied
        model.sendTestNotification(prayer: .asr, kind: .start)
        try await eventually { model.notificationStatusKey == "notifications.denied" }
        XCTAssertFalse(model.canSendTestNotification)
        XCTAssertTrue(notifications.tests.isEmpty)
        XCTAssertEqual(notifications.requests, 0)
    }
    func testProvisionalPermissionAndTestNotificationFailure() async throws {
        let notifications = MockNotifications(); notifications.authorization = .provisional
        let (model, _) = try makeModel(provider: ControlledProvider(), notifications: notifications)
        model.setDeveloperMode(true)
        XCTAssertTrue(model.canSendTestNotification)
        notifications.testFailure = URLError(.unknown)
        model.sendTestNotification(prayer: .isha, kind: .end45)
        try await eventually { model.notificationTestFailureKey == "notifications.test.failed" }
        XCTAssertEqual(model.notificationStatusKey, "notifications.allowed")
        let controller = StatusMenuController(model: model)
        defer { controller.stop(); NSApp.appearance = nil }
        let menu = try XCTUnwrap(controller.menu.items.first { $0.title == model.strings.text("notifications.test") }?.submenu)
        XCTAssertTrue(menu.items.contains { $0.title == model.strings.text("notifications.test.failed") })
        XCTAssertEqual(notifications.requests, 0)
        XCTAssertEqual(notifications.replacementCount, 0)
    }
    func testNotificationRequestsAreImmediateLocalizedAndSeparateFromScheduledAlerts() throws {
        for language in [AppLanguage.en, .da, .tr, .ar] {
            let strings = Localizer(language: language)
            for key in ["notifications.test", "notifications.test.start", "notifications.test.failed"] {
                XCTAssertNotEqual(strings.text(key), key)
            }
            for prayer in Prayer.obligatory {
                for kind in NotificationTestKind.allCases {
                    let request = try NotificationService.testRequest(prayer: prayer, kind: kind, language: language)
                    XCTAssertNil(request.trigger)
                    XCTAssertEqual(request.identifier, "mysalah-test")
                    XCTAssertFalse(request.identifier.hasPrefix("mysalah."))
                    XCTAssertNotNil(request.content.sound)
                    let message = NotificationPlanner.message(prayer: prayer, reminderMinutes: kind.reminderMinutes, language: language)
                    XCTAssertEqual(request.content.title, strings.text("notifications.test.title", message.title))
                    XCTAssertEqual(request.content.body, message.body)
                    XCTAssertFalse(request.content.title.contains("%@"))
                    XCTAssertFalse(request.content.body.contains("%d"))
                    XCTAssertFalse(request.content.body.contains("%@"))
                }
            }
        }
        let start = try NotificationService.testRequest(prayer: .asr, kind: .start, language: .en)
        XCTAssertEqual(start.content.title, "Test: Asr has begun")
        XCTAssertEqual(start.content.body, "It is time for Asr.")
        let end = try NotificationService.testRequest(prayer: .asr, kind: .end15, language: .en)
        XCTAssertEqual(end.content.body, "15 minutes remain in Asr.")
        XCTAssertThrowsError(try NotificationService.testRequest(prayer: .sunrise, kind: .start, language: .en))
    }
    func testSlowPreviousTestFailureCannotReplaceNewerTestResult() async throws {
        let notifications = MockNotifications(); notifications.authorization = .authorized; notifications.suspendTests = true
        let (model, _) = try makeModel(provider: ControlledProvider(), notifications: notifications)
        model.setDeveloperMode(true)
        model.sendTestNotification(prayer: .asr, kind: .start)
        try await eventually { notifications.testWaiters.count == 1 }
        model.sendTestNotification(prayer: .isha, kind: .end30)
        try await eventually { notifications.testWaiters.count == 2 }
        notifications.testWaiters[1].resume()
        try await eventually { notifications.tests.count == 1 }
        notifications.testWaiters[0].resume(throwing: URLError(.unknown))
        try await eventually { notifications.completedTests == 2 }
        XCTAssertEqual(notifications.tests.last?.prayer, .isha)
        XCTAssertNil(model.notificationTestFailureKey)
        XCTAssertEqual(model.notificationStatusKey, "notifications.allowed")
    }
    func testBuiltAppExplicitlyReferencesAReadableStandaloneIcon() throws {
        let app = Bundle(for: Self.self).bundleURL.deletingLastPathComponent().appendingPathComponent("MySalah.app")
        let plist = try PropertyListSerialization.propertyList(from: Data(contentsOf: app.appendingPathComponent("Contents/Info.plist")), format: nil)
        let info = try XCTUnwrap(plist as? [String: Any])
        XCTAssertEqual(info["CFBundleIconFile"] as? String, "MySalah.icns")
        XCTAssertNil(info["CFBundleIconName"])
        let iconURL = app.appendingPathComponent("Contents/Resources/MySalah.icns")
        let icon = try XCTUnwrap(NSImage(contentsOf: iconURL))
        let bitmap = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 64, pixelsHigh: 64, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        bitmap.size = NSSize(width: 64, height: 64)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        icon.draw(in: NSRect(x: 0, y: 0, width: 64, height: 64), from: .zero, operation: .copy, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()
        var bluePixels = 0
        for x in 0..<64 {
            for y in 0..<64 {
                if let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB), color.alphaComponent > 0.5, color.blueComponent > color.redComponent + 0.2 { bluePixels += 1 }
            }
        }
        XCTAssertGreaterThan(bluePixels, 64, "The packaged icon must contain the blue tile, not a blank or generic image")
        let preview = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("build/previews/app-icon.png")
        try FileManager.default.createDirectory(at: preview.deletingLastPathComponent(), withIntermediateDirectories: true)
        try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: preview)
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
