import Foundation

public struct PlannedNotification: Equatable, Sendable, Identifiable {
    public let id: String
    public let date: Date
    public let title: String
    public let body: String
}
public struct NotificationPlanner: Sendable {
    public init() {}
    public static func message(prayer: Prayer, reminderMinutes: Int? = nil, language: AppLanguage) -> (title: String, body: String) {
        let strings = Localizer(language: language)
        if let minutes = reminderMinutes {
            return (strings.text("notification.end.title", strings.name(prayer)), strings.text("notification.end.body", minutes, strings.name(prayer)))
        }
        return (strings.text("notification.start.title", strings.name(prayer)), strings.text("notification.start.body", strings.name(prayer)))
    }
    public func plan(days: [PrayerDay], preferences: Preferences, now: Date, timeZone: TimeZone) -> [PlannedNotification] {
        let prefix = "mysalah.\(preferences.location?.locality.id ?? "unknown")"
        var events: [PlannedNotification] = []
        // Start alerts require a verified start, but do not depend on tomorrow's coverage.
        if preferences.startNotifications {
            for day in days {
                for prayer in Prayer.obligatory {
                    guard let start = day[prayer], start > now else { continue }
                    let message = Self.message(prayer: prayer, language: preferences.language)
                    events.append(PlannedNotification(id: "\(prefix).\(prayer.rawValue).\(Int(start.timeIntervalSince1970)).start", date: start, title: message.title, body: message.body))
                }
            }
        }
        for interval in ScheduleEngine().intervals(days: days, timeZone: timeZone) {
            let minutes = preferences.reminder(for: interval.prayer)
            let fire = interval.end.addingTimeInterval(-Double(minutes * 60))
            guard minutes > 0, fire >= interval.start, fire > now else { continue }
            let message = Self.message(prayer: interval.prayer, reminderMinutes: minutes, language: preferences.language)
            events.append(PlannedNotification(id: "\(prefix).\(interval.prayer.rawValue).\(Int(interval.start.timeIntervalSince1970)).end", date: fire, title: message.title, body: message.body))
        }
        var seen = Set<String>()
        return Array(events.sorted { $0.date == $1.date ? $0.id < $1.id : $0.date < $1.date }.filter { seen.insert($0.id).inserted }.prefix(60))
    }
}
