import AppKit
import Observation
import ServiceManagement
import MySalahCore

@Observable @MainActor final class AppModel {
    var preferences: Preferences
    var days: [PrayerDay] = []
    var now: Date
    var isLoading = false
    var isResolving = false
    var failureKey: String?
    var fetchedAt: Date?
    var usingCache = false
    var pendingLocality: Locality?
    var locationMatches: [LocationMetadata] = []
    var notificationStatusKey = "notifications.unknown"
    var notificationTestFailureKey: String?
    var loginEnabled = false
    var loginRequiresApproval = false
    var onMenuNeedsUpdate: (() -> Void)?

    @ObservationIgnored let provider: any PrayerTimeProvider
    @ObservationIgnored private let resolver: any LocationResolving
    @ObservationIgnored private let cache: DiskCache
    @ObservationIgnored private let store: PreferencesStore
    @ObservationIgnored private let notifications: any NotificationManaging
    @ObservationIgnored private let clock: any AppClock
    @ObservationIgnored private var rawDays: [RawPrayerDay] = []
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private var locationGeneration = UUID()
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    @ObservationIgnored private var selectionTask: Task<Void, Never>?
    @ObservationIgnored private var retryTask: Task<Void, Never>?
    @ObservationIgnored private var retryCount = 0
    @ObservationIgnored private var lastDay: Date?
    @ObservationIgnored private var syncGeneration = UUID()
    @ObservationIgnored private var testGeneration = UUID()
    @ObservationIgnored private var notificationTestTask: Task<Void, Never>?

    init(provider: any PrayerTimeProvider = EzanVaktiProvider(), resolver: any LocationResolving = AppleLocationResolver(), cache: DiskCache = DiskCache(), store: PreferencesStore = PreferencesStore(), notifications: any NotificationManaging = NotificationService(), clock: any AppClock = SystemClock()) {
        self.provider = provider; self.resolver = resolver; self.cache = cache; self.store = store; self.notifications = notifications; self.clock = clock
        preferences = store.load(); now = clock.now()
        refreshLoginStatus()
    }
    var strings: Localizer { Localizer(language: preferences.language) }
    var canSendTestNotification: Bool { preferences.developerMode && (notifications.authorization == .authorized || notifications.authorization == .provisional) }
    var timeZone: TimeZone? { preferences.location?.metadata.timeZone }
    var snapshot: ScheduleSnapshot? {
        guard let zone = timeZone else { return nil }
        return ScheduleEngine().snapshot(days: days, now: now, timeZone: zone)
    }
    var statusText: String {
        if isResolving { return strings.text("status.resolving") }
        if !locationMatches.isEmpty { return strings.text("status.chooseMatch") }
        if isLoading { return strings.text("status.loading") }
        if let failureKey { return strings.text(failureKey) }
        guard preferences.location != nil else { return strings.text("status.selectLocation") }
        guard snapshot?.hasToday == true else { return strings.text("status.noCoverage") }
        if preferences.asrMethod == .hanafi, snapshot?.rows.first(where: { $0.prayer == .asr })?.start == nil { return strings.text("status.asrUnavailable") }
        guard let fetchedAt else { return strings.text("status.noCoverage") }
        guard let zone = timeZone else { return strings.text("status.noCoverage") }
        return strings.text("status.cached", TimeDisplay.clock(fetchedAt, format: preferences.clockFormat, language: strings.language, timeZone: zone))
    }
    func start() { refresh(); syncNotifications(requestPermission: false) }
    func tick() {
        now = clock.now()
        guard let zone = timeZone else { return }
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = zone
        let day = calendar.startOfDay(for: now)
        if day != lastDay {
            lastDay = day
            syncNotifications(requestPermission: false)
            if !isLoading { refresh() }
        }
        else if !isLoading, retryTask == nil, failureKey == nil, let fetchedAt, now.timeIntervalSince(fetchedAt) >= 86_400 { refresh() }
    }
    func wake() {
        now = clock.now(); refreshLoginStatus(); refresh(); syncNotifications(requestPermission: false); onMenuNeedsUpdate?()
    }
    func update(_ mutation: (inout Preferences) -> Void) {
        let oldAsr = preferences.asrMethod
        mutation(&preferences); store.save(preferences)
        if oldAsr != preferences.asrMethod { parseDays() }
        syncNotifications(requestPermission: preferences.startNotifications || preferences.reminders.values.contains(where: { $0 > 0 }))
        onMenuNeedsUpdate?()
    }
    func select(_ locality: Locality) {
        selectionTask?.cancel()
        locationGeneration = UUID(); let token = locationGeneration
        pendingLocality = locality; locationMatches = []; isResolving = true; failureKey = nil
        onMenuNeedsUpdate?()
        selectionTask = Task { [weak self] in
            guard let self else { return }
            if let metadata = await cache.read(LocationMetadata.self, key: "location-\(locality.id)"), metadata.isValid {
                guard token == locationGeneration else { return }
                commitLocation(locality, metadata: metadata); return
            }
            do {
                let matches = try await resolver.resolve(locality)
                guard token == locationGeneration, !Task.isCancelled else { return }
                isResolving = false
                if matches.count == 1, let match = matches.first { commitLocation(locality, metadata: match) }
                else if matches.isEmpty { failureKey = "status.locationFailed" }
                else { locationMatches = matches }
            } catch {
                guard token == locationGeneration, !Task.isCancelled else { return }
                isResolving = false; failureKey = "status.locationFailed"
            }
            onMenuNeedsUpdate?()
        }
    }
    func chooseMatch(_ metadata: LocationMetadata) {
        if let locality = pendingLocality { commitLocation(locality, metadata: metadata) }
    }
    private func commitLocation(_ locality: Locality, metadata: LocationMetadata) {
        guard metadata.isValid else { return }
        refreshTask?.cancel(); retryTask?.cancel(); generation = UUID()
        preferences.location = SelectedLocation(locality: locality, metadata: metadata); store.save(preferences)
        days = []; rawDays = []; fetchedAt = nil; failureKey = nil; retryCount = 0; isLoading = false
        pendingLocality = nil; locationMatches = []; isResolving = false; lastDay = nil
        Task { try? await cache.write(metadata, key: "location-\(locality.id)") }
        syncNotifications(requestPermission: false)
        refresh(); onMenuNeedsUpdate?()
    }
    func retry() {
        if let pendingLocality { select(pendingLocality) }
        else { retryCount = 0; refresh(force: true) }
    }
    func refresh(force: Bool = false) {
        guard let location = preferences.location, let zone = location.metadata.timeZone else { return }
        if isLoading && !force { return }
        refreshTask?.cancel(); retryTask?.cancel(); retryTask = nil
        generation = UUID(); let token = generation
        isLoading = true
        refreshTask = Task { [weak self] in
            guard let self else { return }
            let key = "times-\(location.locality.id)"
            let cached = await cache.read(CachedTimetable.self, key: key)
            guard token == generation, !Task.isCancelled else { return }
            if let cached {
                rawDays = cached.days; fetchedAt = cached.fetchedAt; usingCache = true; parseDays()
                if !force && cached.isFresh(at: clock.now()) && coversTodayAndTomorrow(zone: zone) {
                    isLoading = false; failureKey = nil
                    syncNotifications(requestPermission: true); onMenuNeedsUpdate?(); return
                }
            }
            do {
                let response = try await provider.timetable(districtID: location.locality.district.id)
                guard token == generation, !Task.isCancelled else { return }
                guard !response.isEmpty else { throw DataError.noCoverage }
                _ = try response.map { try $0.parsed(in: zone) }
                var merged = Dictionary(rawDays.map { ($0.date, $0) }, uniquingKeysWith: { _, newer in newer })
                response.forEach { merged[$0.date] = $0 }
                let cutoff = clock.now().addingTimeInterval(-3 * 86_400)
                rawDays = merged.values.filter { ((try? $0.parsed(in: zone).date) ?? .distantPast) > cutoff }
                let timestamp = clock.now()
                fetchedAt = timestamp; usingCache = false; parseDays()
                failureKey = coversTodayAndTomorrow(zone: zone) ? nil : "status.noCoverage"
                retryCount = 0
                do { try await cache.write(CachedTimetable(fetchedAt: timestamp, days: rawDays), key: key) }
                catch { if token == generation { failureKey = "status.cacheFailed" } }
                guard token == generation else { return }
                isLoading = false
                syncNotifications(requestPermission: true)
            } catch {
                guard token == generation, !Task.isCancelled else { return }
                isLoading = false; failureKey = snapshot?.hasToday == true ? "status.offline" : "status.fetchFailed"
                usingCache = !days.isEmpty
                scheduleRetry(token: token)
                syncNotifications(requestPermission: false)
            }
            onMenuNeedsUpdate?()
        }
    }
    private func coversTodayAndTomorrow(zone: TimeZone) -> Bool {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = zone
        guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: now) else { return false }
        return days.contains { calendar.isDate($0.date, inSameDayAs: now) } && days.contains { calendar.isDate($0.date, inSameDayAs: tomorrow) }
    }
    private func parseDays() {
        guard let location = preferences.location, let zone = location.metadata.timeZone else { days = []; return }
        let parsed = rawDays.compactMap { try? $0.parsed(in: zone) }.sorted { $0.date < $1.date }
        days = preferences.asrMethod == .hanafi ? HanafiAsrCalculator().applying(to: parsed, metadata: location.metadata) : parsed
    }
    private func scheduleRetry(token: UUID) {
        let delays: [UInt64] = [30, 120, 600, 3600]
        guard retryCount < delays.count else { return }
        let delay = delays[retryCount]; retryCount += 1
        retryTask = Task { [weak self] in
            do { try await Task.sleep(nanoseconds: delay * 1_000_000_000) } catch { return }
            guard let self, token == generation else { return }
            refresh(force: true)
        }
    }
    func syncNotifications(requestPermission: Bool) {
        syncGeneration = UUID(); let token = syncGeneration
        Task { [weak self] in
            guard let self else { return }
            let hasNotifications = preferences.startNotifications || preferences.reminders.values.contains { $0 > 0 }
            await notifications.updateAuthorization(request: requestPermission && snapshot?.hasToday == true && hasNotifications)
            guard token == syncGeneration else { return }
            updateNotificationStatus()
            let events = timeZone.map { NotificationPlanner().plan(days: days, preferences: preferences, now: clock.now(), timeZone: $0) } ?? []
            do { try await notifications.replace(with: events) }
            catch { if token == syncGeneration { notificationStatusKey = "notifications.failed" } }
            onMenuNeedsUpdate?()
        }
    }
    private func updateNotificationStatus() {
        switch notifications.authorization {
        case .authorized, .provisional: notificationStatusKey = "notifications.allowed"
        case .denied: notificationStatusKey = "notifications.denied"
        default: notificationStatusKey = "notifications.unknown"
        }
    }
    func setDeveloperMode(_ enabled: Bool) {
        preferences.developerMode = enabled
        store.save(preferences)
        if !enabled {
            notificationTestTask?.cancel()
            testGeneration = UUID()
            notificationTestFailureKey = nil
        }
        onMenuNeedsUpdate?()
    }
    func sendTestNotification(prayer: Prayer, kind: NotificationTestKind) {
        guard preferences.developerMode else { return }
        let language = strings.language
        notificationTestTask?.cancel()
        testGeneration = UUID(); let token = testGeneration
        notificationTestTask = Task { [weak self] in
            guard let self else { return }
            notificationTestFailureKey = nil
            await notifications.updateAuthorization(request: false)
            guard token == testGeneration, !Task.isCancelled else { return }
            updateNotificationStatus()
            if canSendTestNotification {
                do { try await notifications.sendTest(prayer: prayer, kind: kind, language: language) }
                catch { if token == testGeneration { notificationTestFailureKey = "notifications.test.failed" } }
            }
            guard token == testGeneration, !Task.isCancelled else { return }
            onMenuNeedsUpdate?()
        }
    }
    func setLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
        } catch { failureKey = "status.loginFailed" }
        refreshLoginStatus(); onMenuNeedsUpdate?()
    }
    func refreshLoginStatus() {
        loginEnabled = SMAppService.mainApp.status == .enabled
        loginRequiresApproval = SMAppService.mainApp.status == .requiresApproval
    }
}
