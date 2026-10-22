import SwiftUI
import BackgroundTasks
import EventKit
import WidgetKit

@main
struct CalendarWidgetApp: App {
    @Environment(\.scenePhase) private var scenePhase
    private static let refreshID = "com.ralphgeb.calendarwidgetapp.refresh"

    init() {
        // iOS wakes the app in the background now and then (when it chooses to).
        // Each time, the widget is told to re-read the calendar.
        BGTaskScheduler.shared.register(forTaskWithIdentifier: Self.refreshID, using: nil) { task in
            Self.scheduleRefresh()
            WidgetCenter.shared.reloadTimelines(ofKind: SharedSettings.widgetKind)
            task.setTaskCompleted(success: true)
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                // Calendar changed while the app is open: refresh the widget straight away.
                .onReceive(NotificationCenter.default.publisher(for: .EKEventStoreChanged)) { _ in
                    WidgetCenter.shared.reloadTimelines(ofKind: SharedSettings.widgetKind)
                }
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                WidgetCenter.shared.reloadTimelines(ofKind: SharedSettings.widgetKind)
            case .background:
                Self.scheduleRefresh()
            default: break
            }
        }
    }

    static func scheduleRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: refreshID)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }
}
