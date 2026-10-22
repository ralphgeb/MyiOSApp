import AppIntents
import WidgetKit

/// Shared paging state (stored in an App Group so the widget can read it).
enum Pager {
    static let key = "rowOffset"
    static let step = 3 // rows moved per tap

    static var defaults: UserDefaults { SharedSettings.defaults }
}

/// Tapped from the widget's up/down buttons. Widgets can't scroll,
/// so this moves a "window" over the event list instead.
struct PageIntent: AppIntent {
    static var title: LocalizedStringResource = "Page events"

    @Parameter(title: "Direction") var delta: Int

    init() {}
    init(delta: Int) { self.delta = delta }

    func perform() async throws -> some IntentResult {
        let current = Pager.defaults.integer(forKey: Pager.key)
        Pager.defaults.set(max(0, current + delta), forKey: Pager.key)
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}
