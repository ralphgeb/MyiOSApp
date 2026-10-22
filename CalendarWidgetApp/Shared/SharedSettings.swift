import Foundation

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
    }

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
}
