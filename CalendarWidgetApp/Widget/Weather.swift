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
        if let cached, Date().timeIntervalSince(cached.fetched) < 20 * 60 {
            return cached
        }

        if let coord = await LocationProvider.coordinate(),
           let fresh = await fetch(lat: coord.lat, lon: coord.lon) {
            SharedSettings.weather = fresh
            return fresh
        }

        // Offline or no location: keep showing a recent value rather than nothing.
        if let cached, Date().timeIntervalSince(cached.fetched) < 6 * 3600 { return cached }
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

extension SharedSettings.WeatherSnapshot {
    /// Outline SF Symbol for the weather code (WMO codes). Drawn ultra-light in the widget.
    var symbolName: String {
        switch code {
        case 0: return isDay ? "sun.max" : "moon.stars"
        case 1, 2: return isDay ? "cloud.sun" : "cloud.moon"
        case 3: return "cloud"
        case 45, 48: return "cloud.fog"
        case 51, 53, 55, 56, 57: return "cloud.drizzle"
        case 61, 63, 80, 81: return "cloud.rain"
        case 65, 82: return "cloud.heavyrain"
        case 66, 67: return "cloud.sleet"
        case 71, 73, 75, 77, 85, 86: return "cloud.snow"
        case 95, 96, 99: return "cloud.bolt.rain"
        default: return "cloud"
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
