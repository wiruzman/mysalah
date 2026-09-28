import Foundation

public protocol PrayerTimeProvider: Sendable {
    func countries() async throws -> [Place]
    func regions(countryID: String) async throws -> [Place]
    func districts(regionID: String) async throws -> [Place]
    func timetable(districtID: String) async throws -> [RawPrayerDay]
}

public struct RawPrayerDay: Codable, Equatable, Sendable {
    public let date: String
    public let fajr: String
    public let sunrise: String
    public let dhuhr: String
    public let asr: String
    public let maghrib: String
    public let isha: String
    enum CodingKeys: String, CodingKey {
        case date = "MiladiTarihKisa", fajr = "Imsak", sunrise = "Gunes", dhuhr = "Ogle", asr = "Ikindi", maghrib = "Aksam", isha = "Yatsi"
    }
    public init(date: String, fajr: String, sunrise: String, dhuhr: String, asr: String, maghrib: String, isha: String) {
        self.date = date; self.fajr = fajr; self.sunrise = sunrise; self.dhuhr = dhuhr; self.asr = asr; self.maghrib = maghrib; self.isha = isha
    }
    public func parsed(in timeZone: TimeZone) throws -> PrayerDay {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = date.split(separator: ".").compactMap { Int($0) }
        guard parts.count == 3, (1...31).contains(parts[0]), (1...12).contains(parts[1]), (2000...2200).contains(parts[2]) else { throw DataError.malformedTimetable }
        let components = DateComponents(year: parts[2], month: parts[1], day: parts[0])
        guard let day = calendar.date(from: components), calendar.dateComponents([.year, .month, .day], from: day) == components else { throw DataError.malformedTimetable }
        let values = [fajr, sunrise, dhuhr, asr, maghrib, isha]
        var times: [Prayer: Date] = [:]
        var previous: Date?
        for (prayer, value) in zip(Prayer.allCases, values) {
            let clock = value.split(separator: ":", omittingEmptySubsequences: false)
            guard clock.count == 2, clock.allSatisfy({ $0.count == 2 }), let hour = Int(clock[0]), let minute = Int(clock[1]), (0...23).contains(hour), (0...59).contains(minute) else { throw DataError.malformedTimetable }
            var targetDay = day
            // In northern summers Isha may occur after civil midnight.
            if prayer == .isha, hour < 12, let tomorrow = calendar.date(byAdding: .day, value: 1, to: day) { targetDay = tomorrow }
            guard let instant = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: targetDay, matchingPolicy: .strict, repeatedTimePolicy: .first, direction: .forward), calendar.isDate(instant, inSameDayAs: targetDay), calendar.component(.hour, from: instant) == hour, calendar.component(.minute, from: instant) == minute, previous.map({ instant > $0 }) ?? true else { throw DataError.malformedTimetable }
            times[prayer] = instant; previous = instant
        }
        return PrayerDay(date: day, timeZoneIdentifier: timeZone.identifier, times: times)
    }
}

public struct EzanVaktiProvider: PrayerTimeProvider {
    private let session: URLSession
    private let baseURL: URL
    public init(session: URLSession = .shared, baseURL: URL = URL(string: "https://ezanvakti.emushaf.net")!) {
        self.session = session; self.baseURL = baseURL
    }
    private func get<T: Decodable & Sendable>(_ path: String) async throws -> T {
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.timeoutInterval = 25
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("MySalah/1.0", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw DataError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else { throw DataError.http(http.statusCode) }
        guard data.count <= 5_000_000 else { throw DataError.invalidResponse }
        return try JSONDecoder().decode(T.self, from: data)
    }
    public func countries() async throws -> [Place] {
        let values: [CountryDTO] = try await get("ulkeler")
        return values.map { Place(id: $0.UlkeID, name: $0.UlkeAdi, englishName: $0.UlkeAdiEn) }
    }
    public func regions(countryID: String) async throws -> [Place] {
        let values: [RegionDTO] = try await get("sehirler/\(countryID)")
        return values.map { Place(id: $0.SehirID, name: $0.SehirAdi, englishName: $0.SehirAdiEn) }
    }
    public func districts(regionID: String) async throws -> [Place] {
        let values: [DistrictDTO] = try await get("ilceler/\(regionID)")
        return values.map { Place(id: $0.IlceID, name: $0.IlceAdi, englishName: $0.IlceAdiEn) }
    }
    public func timetable(districtID: String) async throws -> [RawPrayerDay] {
        try await get("vakitler/\(districtID)")
    }
}
private struct CountryDTO: Decodable, Sendable { let UlkeID: String; let UlkeAdi: String; let UlkeAdiEn: String }
private struct RegionDTO: Decodable, Sendable { let SehirID: String; let SehirAdi: String; let SehirAdiEn: String }
private struct DistrictDTO: Decodable, Sendable { let IlceID: String; let IlceAdi: String; let IlceAdiEn: String }
