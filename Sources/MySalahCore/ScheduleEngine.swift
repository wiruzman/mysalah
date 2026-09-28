import Foundation

public struct PrayerInterval: Equatable, Sendable {
    public let prayer: Prayer
    public let start: Date
    public let end: Date
    public let day: Date
}
public struct PrayerRow: Equatable, Sendable, Identifiable {
    public let prayer: Prayer
    public let start: Date?
    public let isActive: Bool
    public let isYesterday: Bool
    public var id: Prayer { prayer }
}
public struct ScheduleSnapshot: Equatable, Sendable {
    public let date: Date
    public let rows: [PrayerRow]
    public let active: PrayerInterval?
    public let nextBoundary: Date?
    public let nextPrayer: Prayer?
    public let hasToday: Bool
}

public struct ScheduleEngine: Sendable {
    public init() {}
    public func intervals(days: [PrayerDay], timeZone: TimeZone) -> [PrayerInterval] {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = timeZone
        let ordered = days.sorted { $0.date < $1.date }
        var result: [PrayerInterval] = []
        for day in ordered {
            let followingDate = calendar.date(byAdding: .day, value: 1, to: day.date)
            let tomorrow = followingDate.flatMap { date in ordered.first { calendar.isDate($0.date, inSameDayAs: date) } }
            let ends: [Prayer: Date?] = [.fajr: day[.sunrise], .dhuhr: day[.asr], .asr: day[.maghrib], .maghrib: day[.isha], .isha: tomorrow?[.fajr]]
            for prayer in Prayer.obligatory {
                if let start = day[prayer], let end = ends[prayer] ?? nil, end > start {
                    result.append(PrayerInterval(prayer: prayer, start: start, end: end, day: day.date))
                }
            }
        }
        return result.sorted { $0.start < $1.start }
    }
    public func snapshot(days: [PrayerDay], now: Date, timeZone: TimeZone) -> ScheduleSnapshot {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = timeZone
        let today = days.first { calendar.isDate($0.date, inSameDayAs: now) }
        let active = intervals(days: days, timeZone: timeZone).last { $0.start <= now && now < $0.end }
        let upcoming = days.flatMap { day in day.times.map { (prayer: $0.key, start: $0.value) } }.filter { $0.start > now }.sorted { $0.start < $1.start }.first
        let rows = Prayer.allCases.map { prayer in
            let selected = active?.prayer == prayer
            let yesterday = selected && active.map { !calendar.isDate($0.day, inSameDayAs: now) } == true
            return PrayerRow(prayer: prayer, start: yesterday ? active?.start : today?[prayer], isActive: selected, isYesterday: yesterday)
        }
        return ScheduleSnapshot(date: now, rows: rows, active: active, nextBoundary: active?.end ?? upcoming?.start, nextPrayer: upcoming?.prayer, hasToday: today != nil)
    }
}

public enum TimeDisplay {
    public static func countdown(until end: Date, now: Date) -> String {
        let seconds = max(0, Int(ceil(end.timeIntervalSince(now))))
        return seconds >= 3600 ? String(format: "%02d:%02d:%02d", seconds / 3600, (seconds % 3600) / 60, seconds % 60) : String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }
    public static func minutes(until end: Date, now: Date) -> Int { max(0, Int(ceil(end.timeIntervalSince(now) / 60))) }
    public static func clock(_ date: Date, format: ClockFormat, language: AppLanguage, timeZone: TimeZone) -> String {
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: language.resolved().rawValue); formatter.timeZone = timeZone
        switch format {
        case .twelve: formatter.dateFormat = "h:mm a"
        case .twentyFour: formatter.dateFormat = "HH:mm"
        case .system:
            let pattern = DateFormatter.dateFormat(fromTemplate: "j", options: 0, locale: .current) ?? "HH"
            formatter.dateFormat = pattern.contains("a") ? "h:mm a" : "HH:mm"
        }
        return formatter.string(from: date)
    }
}
