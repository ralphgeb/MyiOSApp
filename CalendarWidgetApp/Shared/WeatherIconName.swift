import Foundation

extension SharedSettings.WeatherSnapshot {
    /// Name of the custom icon (see WeatherIconData) for the weather code (WMO codes).
    var iconName: String {
        switch code {
        case 0: return isDay ? "clear-day" : "clear-night"
        case 1, 2: return isDay ? "partly-day" : "partly-night"
        case 3: return "cloudy"
        case 45, 48: return "fog"
        case 51, 53, 55, 56, 57: return "drizzle"
        case 61, 63, 80, 81: return "rain"
        case 65, 82: return "heavy-rain"
        case 66, 67: return "sleet"
        case 71, 73, 75, 77, 85, 86: return "snow"
        case 95, 96, 99: return "thunder"
        default: return "cloudy"
        }
    }
}
