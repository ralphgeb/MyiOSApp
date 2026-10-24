import Foundation
import CoreLocation

/// Current weather for where the user is, using the free Open-Meteo service
/// (no account or key needed). Results are cached in the App Group.
enum WeatherProvider {
    static func current() async -> SharedSettings.WeatherSnapshot? {
        let cached = SharedSettings.weather
        // Weather updates once an hour: reuse the saved value until it is 60 minutes old.
        if let cached, Date().timeIntervalSince(cached.fetched) < 60 * 60 {
            return cached
        }

        // Never slow the widget down: after an attempt, wait 15 minutes before trying again,
        // so taps on the arrows and other refreshes stay instant even if the lookup fails.
        if Date().timeIntervalSince(SharedSettings.weatherLastAttempt) < 15 * 60 {
            if let cached, Date().timeIntervalSince(cached.fetched) < 3 * 3600 { return cached }
            return nil
        }
        SharedSettings.weatherLastAttempt = Date()

        if let coord = await LocationProvider.coordinate(),
           let fresh = await WeatherFetcher.fetch(lat: coord.lat, lon: coord.lon) {
            SharedSettings.weather = fresh
            return fresh
        }

        // Offline or no location: keep showing a recent value rather than nothing.
        if let cached, Date().timeIntervalSince(cached.fetched) < 3 * 3600 { return cached }
        return nil
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
