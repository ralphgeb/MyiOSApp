import AppIntents
import WidgetKit

/// Which page of events the widget shows (stored in the App Group so the widget can read it).
/// Goes back to page 1 if the widget hasn't been touched for 15 minutes.
enum Pager {
    private static let pageKey = "pageIndex"
    private static let touchedKey = "pageTouched"

    static var defaults: UserDefaults { SharedSettings.defaults }

    static var page: Int {
        get {
            let touched = defaults.double(forKey: touchedKey)
            guard touched > 0, Date().timeIntervalSince1970 - touched < 15 * 60 else { return 0 }
            return max(0, defaults.integer(forKey: pageKey))
        }
        set {
            defaults.set(max(0, newValue), forKey: pageKey)
            defaults.set(Date().timeIntervalSince1970, forKey: touchedKey)
        }
    }
}

/// Tapped from the widget's up/down buttons. Widgets can't scroll,
/// so this switches to another page of events instead.
struct PageIntent: AppIntent {
    static var title: LocalizedStringResource = "Show page"

    @Parameter(title: "Page") var target: Int

    init() {}
    init(target: Int) { self.target = target }

    func perform() async throws -> some IntentResult {
        Pager.page = target
        WidgetCenter.shared.reloadTimelines(ofKind: CalendarListWidget.kind)
        return .result()
    }
}
