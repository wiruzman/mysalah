import Foundation
import UserNotifications
import MySalahCore

enum NotificationTestKind: CaseIterable, Equatable, Sendable {
    case start, end15, end30, end45
    var reminderMinutes: Int? {
        switch self { case .start: nil; case .end15: 15; case .end30: 30; case .end45: 45 }
    }
    func title(using strings: Localizer) -> String {
        reminderMinutes.map { strings.text("minutesBefore", $0) } ?? strings.text("notifications.test.start")
    }
}

enum NotificationTestError: Error { case notAuthorized, invalidPrayer }

@MainActor protocol NotificationManaging {
    var authorization: UNAuthorizationStatus { get }
    func updateAuthorization(request: Bool) async
    func replace(with events: [PlannedNotification]) async throws
    func sendTest(prayer: Prayer, kind: NotificationTestKind, language: AppLanguage) async throws
}

@MainActor final class NotificationService: NSObject, UNUserNotificationCenterDelegate, NotificationManaging {
    private let center = UNUserNotificationCenter.current()
    private var revision = 0
    private var replacementTask: Task<Void, Error>?
    private(set) var authorization: UNAuthorizationStatus = .notDetermined
    override init() { super.init(); center.delegate = self }

    func updateAuthorization(request: Bool) async {
        var status = await center.notificationSettings().authorizationStatus
        if request && status == .notDetermined {
            _ = try? await center.requestAuthorization(options: [.alert, .sound])
            status = await center.notificationSettings().authorizationStatus
        }
        authorization = status
    }

    static func testRequest(prayer: Prayer, kind: NotificationTestKind, language: AppLanguage) throws -> UNNotificationRequest {
        guard Prayer.obligatory.contains(prayer) else { throw NotificationTestError.invalidPrayer }
        let message = NotificationPlanner.message(prayer: prayer, reminderMinutes: kind.reminderMinutes, language: language)
        let content = UNMutableNotificationContent()
        content.title = Localizer(language: language).text("notifications.test.title", message.title)
        content.body = message.body; content.sound = .default
        // Immediate delivery leaves the rolling timetable's 60 pending slots alone.
        // Reuse one separate identifier so repeated tests replace the previous test.
        return UNNotificationRequest(identifier: "mysalah-test", content: content, trigger: nil)
    }

    func sendTest(prayer: Prayer, kind: NotificationTestKind, language: AppLanguage) async throws {
        guard authorization == .authorized || authorization == .provisional else { throw NotificationTestError.notAuthorized }
        try await center.add(Self.testRequest(prayer: prayer, kind: kind, language: language))
    }

    func replace(with events: [PlannedNotification]) async throws {
        revision += 1
        let currentRevision = revision
        let previous = replacementTask
        let task = Task { [weak self] in
            _ = try? await previous?.value
            guard let self, currentRevision == revision else { return }
            try await apply(events, revision: currentRevision)
        }
        replacementTask = task
        try await task.value
    }

    private func apply(_ events: [PlannedNotification], revision currentRevision: Int) async throws {
        let pending = await center.pendingNotificationRequests()
        guard currentRevision == revision else { return }
        let desired = Dictionary(uniqueKeysWithValues: events.map { ($0.id, $0) })
        center.removePendingNotificationRequests(withIdentifiers: pending.filter { $0.identifier.hasPrefix("mysalah.") && desired[$0.identifier] == nil }.map(\.identifier))
        guard authorization == .authorized || authorization == .provisional else {
            center.removePendingNotificationRequests(withIdentifiers: pending.filter { $0.identifier.hasPrefix("mysalah.") }.map(\.identifier))
            return
        }
        for event in events {
            guard currentRevision == revision else { return }
            guard event.date > Date() else { continue }
            let content = UNMutableNotificationContent()
            content.title = event.title; content.body = event.body; content.sound = .default
            // Absolute UTC components prevent device timezone changes from moving alerts.
            var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 0)!
            var components = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: event.date)
            components.timeZone = calendar.timeZone
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            try await center.add(UNNotificationRequest(identifier: event.id, content: content, trigger: trigger))
        }
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }
}
