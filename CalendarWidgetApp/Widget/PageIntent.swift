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

    private static let familyKey = "pageFamily"

    /// The page for this widget size. A different size always starts on page 1, so changing
    /// the widget's size never leaves it on a later page. Also resets after 15 idle minutes.
    static func page(for family: WidgetFamily) -> Int {
        guard defaults.string(forKey: familyKey) == "\(family)" else { return 0 }
        let touched = defaults.double(forKey: touchedKey)
        guard touched > 0, Date().timeIntervalSince1970 - touched < 15 * 60 else { return 0 }
        return max(0, defaults.integer(forKey: pageKey))
    }

    static func set(page: Int, for family: String) {
        defaults.set(max(0, page), forKey: pageKey)
        defaults.set(family, forKey: familyKey)
        defaults.set(Date().timeIntervalSince1970, forKey: touchedKey)
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

    private var currentPage: Int { max(0, Pager.defaults.integer(forKey: "pageIndex")) }

    func perform() async throws -> some IntentResult {
        Pager.direction = target >= currentPage ? 1 : -1
        Pager.set(page: target, for: family)
        WidgetCenter.shared.reloadTimelines(ofKind: CalendarListWidget.kind)
        return .result()
    }
}
