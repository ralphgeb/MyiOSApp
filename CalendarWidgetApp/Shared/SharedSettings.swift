import SwiftUI
import UIKit

/// A colour that can be stored in the App Group (Color itself isn't Codable).
struct RGBA: Codable, Equatable {
    var r: Double
    var g: Double
    var b: Double
    var a: Double

    var color: Color { Color(.sRGB, red: r, green: g, blue: b, opacity: a) }

    init(r: Double, g: Double, b: Double, a: Double) {
        self.r = r; self.g = g; self.b = b; self.a = a
    }

    init(_ color: Color) {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(color).getRed(&r, green: &g, blue: &b, alpha: &a)
        func clamp(_ v: CGFloat) -> Double { min(max(Double(v), 0), 1) }
        self.init(r: clamp(r), g: clamp(g), b: clamp(b), a: clamp(a))
    }
}

/// Settings written by the app and read by the widget.
/// Both targets compile this file, and both read the same App Group storage.
enum SharedSettings {
    static let appGroup = "group.com.ralphgeb.calendarwidgetapp" // must match project.yml

    static var defaults: UserDefaults {
        UserDefaults(suiteName: appGroup) ?? .standard
    }

    private enum Key {
        static let hiddenCalendars = "hiddenCalendarIDs"
        static let daysAhead = "daysAhead"
        static let showAllDay = "showAllDayEvents"
        static let background = "backgroundColor"
        static let text = "textColor"
        static let weather = "weatherSnapshot"
        static let coordinate = "lastCoordinate"
    }

    // MARK: Calendars and options

    /// Calendars the user switched OFF. Storing the hidden ones (not the shown ones)
    /// means a newly created calendar appears in the widget by default.
    static var hiddenCalendarIDs: Set<String> {
        get { Set(defaults.stringArray(forKey: Key.hiddenCalendars) ?? []) }
        set { defaults.set(Array(newValue), forKey: Key.hiddenCalendars) }
    }

    /// How many days (including today) the widget lists. Default 4.
    static var daysAhead: Int {
        get {
            let v = defaults.integer(forKey: Key.daysAhead)
            return v == 0 ? 4 : min(max(v, 1), 7)
        }
        set { defaults.set(min(max(newValue, 1), 7), forKey: Key.daysAhead) }
    }

    static var showAllDay: Bool {
        get { defaults.object(forKey: Key.showAllDay) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Key.showAllDay) }
    }

    // MARK: Colours (nil = default: transparent background, system text colour)

    static var backgroundColor: RGBA? {
        get { load(Key.background) }
        set { save(newValue, Key.background) }
    }

    static var textColor: RGBA? {
        get { load(Key.text) }
        set { save(newValue, Key.text) }
    }

    static func resetColors() {
        backgroundColor = nil
        textColor = nil
    }

    // MARK: Weather cache (written by the widget)

    struct WeatherSnapshot: Codable {
        var code: Int
        var isDay: Bool
        var fetched: Date
    }

    struct Coordinate: Codable {
        var lat: Double
        var lon: Double
    }

    static var weather: WeatherSnapshot? {
        get { load(Key.weather) }
        set { save(newValue, Key.weather) }
    }

    static var lastCoordinate: Coordinate? {
        get { load(Key.coordinate) }
        set { save(newValue, Key.coordinate) }
    }

    // MARK: Helpers

    private static func load<T: Decodable>(_ key: String) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    private static func save<T: Encodable>(_ value: T?, _ key: String) {
        if let value, let data = try? JSONEncoder().encode(value) {
            defaults.set(data, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }
}
