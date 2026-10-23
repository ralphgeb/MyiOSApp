import SwiftUI
import BackgroundTasks
import EventKit
import WidgetKit

@main
struct CalendarWidgetApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var location = LocationAccess()
    private static let refreshID = "com.ralphgeb.calendarwidgetapp.refresh"

    init() {
        // iOS wakes the app in the background now and then (when it chooses to).
        // Each time, the widget is told to re-read the calendar.
        BGTaskScheduler.shared.register(forTaskWithIdentifier: Self.refreshID, using: nil) { task in
            Self.scheduleRefresh()
            SharedSettings.reloadWidgets()
            task.setTaskCompleted(success: true)
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(location)
                // Calendar changed while the app is open: refresh the widget straight away.
                .onReceive(NotificationCenter.default.publisher(for: .EKEventStoreChanged)) { _ in
                    SharedSettings.reloadWidgets()
                }
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                SharedSettings.reloadWidgets()
            case .inactive, .background:
                // Changes made in Settings reach the widget even if you leave the app quickly.
                SharedSettings.reloadWidgets()
                if phase == .background { Self.scheduleRefresh() }
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
