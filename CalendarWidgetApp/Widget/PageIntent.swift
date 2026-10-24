import AppIntents
import WidgetKit

/// Which page of events the widget shows (stored in the App Group so the widget can read it).
/// Goes back to page 1 if the widget hasn't been touched for 15 minutes.
enum Pager {
    private static let pageKey = "pageIndex"
    private static let touchedKey = "pageTouched"

    static var defaults: UserDefaults { SharedSettings.defaults }

    /// +1 when the last tap went down, -1 when it went up (decides which way the list slides).
    static var direction: Int {
        get { defaults.integer(forKey: "pageDirection") >= 0 ? 1 : -1 }
        set { defaults.set(newValue >= 0 ? 1 : -1, forKey: "pageDirection") }
    }

    private static func pageKey(_ f: String) -> String { "page_\(f)" }
    private static func touchedKey(_ f: String) -> String { "touched_\(f)" }

    /// The page for this widget size.
    /// - A size you switch to always starts on page 1 (resizing a widget resets it).
    /// - Two sizes on screen at once refresh together, so they don't reset each other:
    ///   a switch only counts when the other size hasn't been refreshed for 5 seconds.
    /// - Also goes back to page 1 after 15 idle minutes.
    static func page(for family: WidgetFamily) -> Int {
        let f = "\(family)"
        let now = Date().timeIntervalSince1970
        let active = defaults.string(forKey: "pageActiveFamily")
        let seen = defaults.double(forKey: "pageActiveSeen")
        if active != f && now - seen > 5 {
            defaults.set(0, forKey: pageKey(f))
            defaults.set(0.0, forKey: touchedKey(f))
            defaults.set(f, forKey: "pageActiveFamily")
        }
        if defaults.string(forKey: "pageActiveFamily") == f { defaults.set(now, forKey: "pageActiveSeen") }

        let touched = defaults.double(forKey: touchedKey(f))
        guard touched > 0, now - touched < 15 * 60 else { return 0 }
        return max(0, defaults.integer(forKey: pageKey(f)))
    }

    static func currentPage(for family: String) -> Int { max(0, defaults.integer(forKey: pageKey(family))) }

    static func set(page: Int, for family: String) {
        let now = Date().timeIntervalSince1970
        defaults.set(max(0, page), forKey: pageKey(family))
        defaults.set(now, forKey: touchedKey(family))
        defaults.set(family, forKey: "pageActiveFamily")
        defaults.set(now, forKey: "pageActiveSeen")
    }
}

/// Tapped from the widget's up/down buttons. Widgets can't scroll,
/// so this switches to another page of events instead.
struct PageIntent: AppIntent {
    static var title: LocalizedStringResource = "Show page"

    @Parameter(title: "Page") var target: Int
    @Parameter(title: "Size") var family: String

    init() {}
    init(target: Int, family: String) { self.target = target; self.family = family }

    func perform() async throws -> some IntentResult {
        Pager.direction = target >= Pager.currentPage(for: family) ? 1 : -1
        Pager.set(page: target, for: family)
        SharedSettings.pagingLog = "\(Date().formatted(date: .omitted, time: .standard)): page \(target + 1), \(family)"
        WidgetCenter.shared.reloadTimelines(ofKind: CalendarListWidget.kind)
        return .result()
    }
}
