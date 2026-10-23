import SwiftUI
import UIKit
import WidgetKit

/// A colour that can be stored in the App Group (Color itself isn't Codable).
struct RGBA: Codable, Equatable {
    var r: Double
    var g: Double
    var b: Double
    var a: Double

    /// Always a solid colour (no transparency).
    var color: Color { Color(.sRGB, red: r, green: g, blue: b, opacity: 1) }

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
    static let widgetKind = "CalendarListWidget"
    static let nextEventKind = "NextEventLockWidget"

    /// Refresh every widget this app offers (battery: only these two kinds, never "all").
    static func reloadWidgets() {
        WidgetCenter.shared.reloadTimelines(ofKind: widgetKind)
        WidgetCenter.shared.reloadTimelines(ofKind: nextEventKind)
    }

    static var defaults: UserDefaults {
        UserDefaults(suiteName: appGroup) ?? .standard
    }

    private enum Key {
        static let hiddenCalendars = "hiddenCalendarIDs"
        static let daysAhead = "daysAhead"
        static let showAllDay = "showAllDayEvents"
        static let colorsBoth = "colorsBoth"
        static let colorsLight = "colorsLight"
        static let colorsDark = "colorsDark"
        static let ignoreAppearance = "ignoreAppearance"
        static let weather = "weatherSnapshot"
        static let coordinate = "lastCoordinate"
        static let isPro = "isPro"
        static let testUnlock = "testUnlock"
    }

    // MARK: Purchase (written by the app, read by the widget)

    /// True once the one-time unlock has been bought. While false, the widget ignores the
    /// calendar and colour settings.
    static var isPro: Bool {
        get { defaults.bool(forKey: Key.isPro) }
        set { defaults.set(newValue, forKey: Key.isPro) }
    }

    /// TestFlight-only shortcut used before the product exists in App Store Connect.
    static var testUnlock: Bool {
        get { defaults.bool(forKey: Key.testUnlock) }
        set { defaults.set(newValue, forKey: Key.testUnlock) }
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

    /// Background and text colour. Either can be nil, which means "use the default".
    struct ColorSet: Codable, Equatable {
        var background: RGBA?
        var text: RGBA?
        var highlight: RGBA?      // colour of the event happening now (default orange)
        var isEmpty: Bool { background == nil && text == nil && highlight == nil }
    }

    /// Everything the widget needs to pick its colours.
    /// When `ignoreAppearance` is on, one set (`both`) is used in Light and Dark mode.
    /// When it's off, Light and Dark mode each keep their own set.
    struct ColorSettings {
        var ignoreAppearance: Bool
        var both: ColorSet
        var light: ColorSet
        var dark: ColorSet

        func resolved(for scheme: ColorScheme) -> ColorSet {
            if ignoreAppearance { return both }
            return scheme == .dark ? dark : light
        }
    }

    static var colorSettings: ColorSettings {
        ColorSettings(ignoreAppearance: ignoreAppearance,
                      both: load(Key.colorsBoth) ?? ColorSet(),
                      light: load(Key.colorsLight) ?? ColorSet(),
                      dark: load(Key.colorsDark) ?? ColorSet())
    }

    static var ignoreAppearance: Bool {
        get { defaults.object(forKey: Key.ignoreAppearance) as? Bool ?? false }
        set { defaults.set(newValue, forKey: Key.ignoreAppearance) }
    }

    /// True once the user has changed any colour from the original.
    static var hasCustomColors: Bool {
        let c = colorSettings
        return !(c.both.isEmpty && c.light.isEmpty && c.dark.isEmpty)
    }

    /// The colours currently being edited: the shared set if the toggle is on, otherwise the
    /// set for the mode the phone is in right now.
    static func editableColors(for scheme: ColorScheme) -> ColorSet {
        colorSettings.resolved(for: scheme)
    }

    static func updateColors(for scheme: ColorScheme, _ change: (inout ColorSet) -> Void) {
        let key = ignoreAppearance ? Key.colorsBoth : (scheme == .dark ? Key.colorsDark : Key.colorsLight)
        var set: ColorSet = load(key) ?? ColorSet()
        change(&set)
        save(set.isEmpty ? nil : set, key)
    }

    /// Turning the toggle on makes the colours you see right now apply in both modes.
    static func setIgnoreAppearance(_ on: Bool, currentScheme: ColorScheme) {
        if on {
            let current = colorSettings.resolved(for: currentScheme)
            save(current.isEmpty ? nil : current, Key.colorsBoth)
        }
        ignoreAppearance = on
    }

    /// Back to the original look, and the toggle goes off.
    static func resetColors() {
        save(nil as ColorSet?, Key.colorsBoth)
        save(nil as ColorSet?, Key.colorsLight)
        save(nil as ColorSet?, Key.colorsDark)
        ignoreAppearance = false
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
