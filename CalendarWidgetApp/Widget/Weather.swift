import Foundation
import CoreLocation

/// Current weather for where the user is, using the free Open-Meteo service
/// (no account or key needed). Results are cached in the App Group.
enum WeatherProvider {
    /// Makes sure the saved 24-hour forecast is good enough. It only calls WeatherKit when the
    /// saved hours are running out or the phone has moved a long way (see `weatherNeedsRefresh`).
    static func refreshIfNeeded() async {
        // Checking where the phone is costs a little battery, so do it at most every 2 hours.
        let lastCheck = Date(timeIntervalSince1970: UserDefaults(suiteName: SharedSettings.appGroup)?
            .double(forKey: "weatherLastLocationCheck") ?? 0)
        let haveForecast = SharedSettings.forecast.map { $0.coveredUntil > Date() } ?? false
        if haveForecast, Date().timeIntervalSince(lastCheck) < 2 * 3600,
           let saved = SharedSettings.lastCoordinate,
           !SharedSettings.weatherNeedsRefresh(lat: saved.lat, lon: saved.lon) {
            return
        }
        UserDefaults(suiteName: SharedSettings.appGroup)?
            .set(Date().timeIntervalSince1970, forKey: "weatherLastLocationCheck")

        guard let coord = await LocationProvider.coordinate(),
              SharedSettings.weatherNeedsRefresh(lat: coord.lat, lon: coord.lon) else { return }
        if let fresh = await WeatherFetcher.fetch(lat: coord.lat, lon: coord.lon) {
            SharedSettings.forecast = fresh
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
                try? await Task.sleep(nanoseconds: 3_000_000_000)   // give up after 3 s
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

/// Runs `operation` but gives up after `seconds`, returning nil.
func withTimeout<T>(_ seconds: Double, _ operation: @escaping () async -> T?) async -> T? {
    await withTaskGroup(of: T?.self) { group in
        group.addTask { await operation() }
        group.addTask {
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            return nil
        }
        let first = await group.next() ?? nil
        group.cancelAll()
        return first
    }
}
