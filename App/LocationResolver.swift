import CoreLocation
import MySalahCore

@MainActor protocol LocationResolving {
    func resolve(_ locality: Locality) async throws -> [LocationMetadata]
}

@MainActor final class AppleLocationResolver: LocationResolving {
    func resolve(_ locality: Locality) async throws -> [LocationMetadata] {
        let geocoder = CLGeocoder()
        let placemarks = try await geocoder.geocodeAddressString(locality.searchQuery, in: nil, preferredLocale: Locale(identifier: "en"))
        var seen = Set<String>()
        return placemarks.compactMap { placemark in
            guard let coordinate = placemark.location?.coordinate, let zone = placemark.timeZone else { return nil }
            let label = [placemark.locality ?? placemark.name, placemark.administrativeArea, placemark.country].compactMap { $0 }.joined(separator: ", ")
            let result = LocationMetadata(latitude: coordinate.latitude, longitude: coordinate.longitude, timeZoneIdentifier: zone.identifier, label: label)
            return result.isValid && seen.insert(result.id).inserted ? result : nil
        }
    }
}
