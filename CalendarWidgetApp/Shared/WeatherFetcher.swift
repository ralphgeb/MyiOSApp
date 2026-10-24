import Foundation
import CoreLocation
import WeatherKit

/// Looks up the current weather with Apple WeatherKit (free with the developer account).
/// Used by the widget and by the app, so the icon can appear as soon as location is allowed.
enum WeatherFetcher {
    /// One WeatherKit call (hourly data only) gives the next 24 hours.
    static func fetch(lat: Double, lon: Double) async -> SharedSettings.WeatherForecast? {
        SharedSettings.weatherLastAttempt = Date()
        do {
            let hourly = try await WeatherService.shared.weather(for: CLLocation(latitude: lat, longitude: lon),
                                                                  including: .hourly)
            let now = Date()
            let hours = hourly.forecast
                .filter { $0.date.addingTimeInterval(3600) > now }
                .prefix(24)
                .map { SharedSettings.WeatherForecast.Hour(start: $0.date,
                                                           code: wmoCode(for: $0.condition.rawValue),
                                                           isDay: $0.isDaylight) }
            guard !hours.isEmpty else { return nil }
            return SharedSettings.WeatherForecast(fetched: now, lat: lat, lon: lon, hours: Array(hours))
        } catch {
            return nil
        }
    }

    /// Turns a WeatherKit condition into the weather code the icon picker already understands.
    private static func wmoCode(for condition: String) -> Int {
        switch condition {
        case "clear", "hot", "frigid": return 0
        case "mostlyClear": return 1
        case "partlyCloudy": return 2
        case "mostlyCloudy", "cloudy", "windy", "breezy", "blowingDust": return 3
        case "foggy", "haze", "smoky": return 45
        case "drizzle": return 51
        case "freezingDrizzle": return 56
        case "rain": return 63
        case "sunShowers": return 80
        case "heavyRain": return 65
        case "freezingRain": return 66
        case "sleet", "wintryMix", "hail": return 67
        case "snow", "flurries", "heavySnow", "blizzard", "blowingSnow", "sunFlurries": return 73
        case "thunderstorms", "isolatedThunderstorms", "scatteredThunderstorms", "strongStorms",
             "tropicalStorm", "hurricane": return 95
        default: return 3
        }
    }
}
