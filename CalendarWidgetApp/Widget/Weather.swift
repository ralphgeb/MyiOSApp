import Foundation
import CoreLocation

/// Current weather for where the user is, using the free Open-Meteo service
/// (no account or key needed). Results are cached in the App Group.
enum WeatherProvider {
    private struct Response: Decodable {
        struct Current: Decodable {
            let weather_code: Int
            let is_day: Int
        }
        let current: Current
    }

    static func current() async -> SharedSettings.WeatherSnapshot? {
        let cached = SharedSettings.weather
        // Weather updates once an hour: reuse the saved value until it is 60 minutes old.
        if let cached, Date().timeIntervalSince(cached.fetched) < 60 * 60 {
            return cached
        }

        if let coord = await LocationProvider.coordinate(),
           let fresh = await fetch(lat: coord.lat, lon: coord.lon) {
            SharedSettings.weather = fresh
            return fresh
        }

        // Offline or no location: keep showing a recent value rather than nothing.
        if let cached, Date().timeIntervalSince(cached.fetched) < 3 * 3600 { return cached }
        return nil
    }

    private static func fetch(lat: Double, lon: Double) async -> SharedSettings.WeatherSnapshot? {
        var comps = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        comps.queryItems = [
            URLQueryItem(name: "latitude", value: String(format: "%.3f", lat)),
            URLQueryItem(name: "longitude", value: String(format: "%.3f", lon)),
            URLQueryItem(name: "current", value: "weather_code,is_day"),
        ]
        guard let url = comps.url else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 8

        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            let r = try JSONDecoder().decode(Response.self, from: data)
            return SharedSettings.WeatherSnapshot(code: r.current.weather_code,
                                                  isDay: r.current.is_day == 1,
                                                  fetched: Date())
        } catch {
            return nil
        }
    }
}

/// One-shot location lookup from inside the widget.
/// Needs "While Using" location permission granted in the app, plus NSWidgetWantsLocation.
@MainActor
final class LocationProvider: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<CLLocation?, Never>?

    static func coordinate() async -> SharedSettings.Coordinate? {
        let provider = LocationProvider()
        if let loc = await provider.requestOnce() {
            let c = SharedSettings.Coordinate(lat: loc.coordinate.latitude, lon: loc.coordinate.longitude)
            SharedSettings.lastCoordinate = c
            return c
        }
        return SharedSettings.lastCoordinate   // saved by the app or an earlier refresh
    }

    private func requestOnce() async -> CLLocation? {
        let status = manager.authorizationStatus
        guard status == .authorizedWhenInUse || status == .authorizedAlways else { return nil }
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer

        return await withCheckedContinuation { cont in
            continuation = cont
            manager.requestLocation()
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 8_000_000_000)   // give up after 8 s
                self.finish(self.manager.location)
            }
        }
    }

    private func finish(_ location: CLLocation?) {
        continuation?.resume(returning: location)
        continuation = nil
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let last = locations.last
        Task { @MainActor in self.finish(last) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in self.finish(self.manager.location) }
    }
}
