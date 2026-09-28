import Foundation

public struct CachedTimetable: Codable, Sendable {
    public let fetchedAt: Date
    public let days: [RawPrayerDay]
    public init(fetchedAt: Date, days: [RawPrayerDay]) { self.fetchedAt = fetchedAt; self.days = days }
    public func isFresh(at now: Date) -> Bool { (0..<86_400).contains(now.timeIntervalSince(fetchedAt)) }
}

public actor DiskCache {
    private let directory: URL
    public init(directory: URL = URL.applicationSupportDirectory.appendingPathComponent("MySalah", isDirectory: true)) { self.directory = directory }
    private func url(_ key: String) -> URL {
        let safe = key.utf8.map { String(format: "%02x", $0) }.joined()
        return directory.appendingPathComponent(safe + ".json")
    }
    public func read<T: Decodable & Sendable>(_ type: T.Type, key: String) -> T? {
        guard let data = try? Data(contentsOf: url(key)) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
    public func write<T: Encodable & Sendable>(_ value: T, key: String) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try JSONEncoder().encode(value).write(to: url(key), options: .atomic)
    }
}

@MainActor public final class PreferencesStore {
    private let defaults: UserDefaults
    private let key = "mysalah.preferences.v1"
    public init(defaults: UserDefaults = .standard) { self.defaults = defaults }
    public func load() -> Preferences {
        defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(Preferences.self, from: $0) } ?? Preferences()
    }
    public func save(_ preferences: Preferences) { defaults.set(try? JSONEncoder().encode(preferences), forKey: key) }
}
