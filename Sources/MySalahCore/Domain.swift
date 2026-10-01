import Foundation

public enum Prayer: String, CaseIterable, Codable, Sendable {
    case fajr, sunrise, dhuhr, asr, maghrib, isha
    public static var obligatory: [Prayer] { allCases.filter { $0 != .sunrise } }
}

public enum Theme: String, CaseIterable, Codable, Sendable { case system, light, dark }
public enum AppLanguage: String, CaseIterable, Codable, Sendable {
    case system, en, da, tr, ar
    public var nativeName: String {
        switch self { case .system: "System"; case .en: "English"; case .da: "Dansk"; case .tr: "Türkçe"; case .ar: "العربية" }
    }
    public func resolved(preferred: [String] = Locale.preferredLanguages) -> AppLanguage {
        guard self == .system else { return self }
        for identifier in preferred {
            let code = identifier.replacingOccurrences(of: "_", with: "-").split(separator: "-").first.map(String.init) ?? ""
            if let match = AppLanguage(rawValue: code), match != .system { return match }
        }
        return .en
    }
}
public enum ClockFormat: String, CaseIterable, Codable, Sendable { case system, twelve, twentyFour }
public enum AsrMethod: String, CaseIterable, Codable, Sendable { case diyanet, hanafi }

public struct Place: Codable, Hashable, Sendable, Identifiable {
    public let id: String
    public let name: String
    public let englishName: String
    public init(id: String, name: String, englishName: String) {
        self.id = id; self.name = name; self.englishName = englishName
    }
    public func displayName(language: AppLanguage) -> String {
        language.resolved() == .tr || englishName.isEmpty ? name : englishName
    }
}

public struct Locality: Codable, Equatable, Sendable {
    public let country: Place
    public let region: Place
    public let district: Place
    public init(country: Place, region: Place, district: Place) {
        self.country = country; self.region = region; self.district = district
    }
    public var id: String { "\(country.id)-\(region.id)-\(district.id)" }
    public var searchQuery: String {
        [district.englishName, region.englishName, country.englishName].reduce(into: [String]()) { result, name in
            if !result.contains(name) && !name.isEmpty { result.append(name) }
        }.joined(separator: ", ")
    }
}

public struct LocationMetadata: Codable, Equatable, Sendable, Identifiable {
    public let latitude: Double
    public let longitude: Double
    public let timeZoneIdentifier: String
    public let label: String
    public var id: String { "\(latitude),\(longitude),\(timeZoneIdentifier)" }
    public var timeZone: TimeZone? { TimeZone(identifier: timeZoneIdentifier) }
    public var isValid: Bool {
        latitude.isFinite && longitude.isFinite && (-90...90).contains(latitude) && (-180...180).contains(longitude) && timeZone != nil
    }
    public init(latitude: Double, longitude: Double, timeZoneIdentifier: String, label: String) {
        self.latitude = latitude; self.longitude = longitude; self.timeZoneIdentifier = timeZoneIdentifier; self.label = label
    }
}

public struct SelectedLocation: Codable, Equatable, Sendable {
    public let locality: Locality
    public let metadata: LocationMetadata
    public init(locality: Locality, metadata: LocationMetadata) { self.locality = locality; self.metadata = metadata }
}

public struct Preferences: Codable, Equatable, Sendable {
    public var theme: Theme = .system
    public var language: AppLanguage = .system
    public var clockFormat: ClockFormat = .system
    public var asrMethod: AsrMethod = .diyanet
    public var startNotifications = true
    public var developerMode = false
    public var reminders: [Prayer: Int] = [:]
    public var location: SelectedLocation?
    public init() {}
    private enum CodingKeys: String, CodingKey {
        case theme, language, clockFormat, asrMethod, startNotifications, developerMode, reminders, location
    }
    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        theme = try values.decode(Theme.self, forKey: .theme)
        language = try values.decode(AppLanguage.self, forKey: .language)
        clockFormat = try values.decode(ClockFormat.self, forKey: .clockFormat)
        asrMethod = try values.decode(AsrMethod.self, forKey: .asrMethod)
        startNotifications = try values.decode(Bool.self, forKey: .startNotifications)
        developerMode = try values.decodeIfPresent(Bool.self, forKey: .developerMode) ?? false
        reminders = try values.decode([Prayer: Int].self, forKey: .reminders)
        location = try values.decodeIfPresent(SelectedLocation.self, forKey: .location)
    }
    public func reminder(for prayer: Prayer) -> Int {
        let value = reminders[prayer] ?? 0
        return prayer != .sunrise && [15, 30, 45].contains(value) ? value : 0
    }
    public mutating func setAllReminders(_ minutes: Int) {
        for prayer in Prayer.obligatory { reminders[prayer] = [15, 30, 45].contains(minutes) ? minutes : 0 }
    }
    public var sharedReminder: Int? {
        let values = Set(Prayer.obligatory.map { reminder(for: $0) })
        return values.count == 1 ? values.first : nil
    }
}

public struct PrayerDay: Codable, Equatable, Sendable {
    public let date: Date
    public let timeZoneIdentifier: String
    public var times: [Prayer: Date]
    public init(date: Date, timeZoneIdentifier: String, times: [Prayer: Date]) {
        self.date = date; self.timeZoneIdentifier = timeZoneIdentifier; self.times = times
    }
    public subscript(_ prayer: Prayer) -> Date? { times[prayer] }
}

public enum DataError: Error, Equatable, Sendable {
    case invalidResponse, http(Int), malformedTimetable, unavailableLocation, noCoverage
}

public protocol AppClock: Sendable { func now() -> Date }
public struct SystemClock: AppClock {
    public init() {}
    public func now() -> Date { Date() }
}
