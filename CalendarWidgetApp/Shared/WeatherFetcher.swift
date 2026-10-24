import Foundation
import CoreLocation
import WeatherKit

/// Looks up the current weather with Apple WeatherKit (free with the developer account).
/// Used by the widget and by the app, so the icon can appear as soon as location is allowed.
enum WeatherFetcher {
    static func fetch(lat: Double, lon: Double) async -> SharedSettings.WeatherSnapshot? {
        do {
            let weather = try await WeatherService.shared.weather(for: CLLocation(latitude: lat, longitude: lon),
                                                                   including: .current)
            SharedSettings.weatherError = nil
            return SharedSettings.WeatherSnapshot(code: wmoCode(for: weather.condition.rawValue),
                                                  isDay: weather.isDaylight,
                                                  fetched: Date())
        } catch {
            SharedSettings.weatherError = String(String(describing: error).prefix(300))
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
