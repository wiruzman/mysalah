import Foundation
import Adhan

public protocol AsrCalculating: Sendable {
    func hanafiAsr(on day: PrayerDay, metadata: LocationMetadata) -> Date?
}

public struct HanafiAsrCalculator: AsrCalculating {
    public init() {}
    public func hanafiAsr(on day: PrayerDay, metadata: LocationMetadata) -> Date? {
        guard metadata.isValid, let zone = metadata.timeZone else { return nil }
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = zone
        let date = calendar.dateComponents([.year, .month, .day], from: day.date)
        // MWL has no Asr adjustment. Its twilight angles are irrelevant: we use only Asr.
        var parameters = CalculationMethod.muslimWorldLeague.params
        parameters.madhab = .hanafi
        parameters.rounding = .up
        guard let result = PrayerTimes(coordinates: Coordinates(latitude: metadata.latitude, longitude: metadata.longitude), date: date, calculationParameters: parameters)?.asr,
              let dhuhr = day[.dhuhr], let maghrib = day[.maghrib],
              result > dhuhr, result < maghrib, calendar.isDate(result, inSameDayAs: day.date) else { return nil }
        return result
    }
    public func applying(to days: [PrayerDay], metadata: LocationMetadata) -> [PrayerDay] {
        days.map { day in
            var adjusted = day
            adjusted.times[.asr] = hanafiAsr(on: day, metadata: metadata)
            return adjusted
        }
    }
}
