import Foundation

/// Looks up the current weather from Open-Meteo (free, no account needed).
/// Used by the widget and by the app, so the icon can appear as soon as location is allowed.
enum WeatherFetcher {
    private struct Response: Decodable {
        struct Current: Decodable {
            let weather_code: Int
            let is_day: Int
        }
        let current: Current
    }

    static func fetch(lat: Double, lon: Double) async -> SharedSettings.WeatherSnapshot? {
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
