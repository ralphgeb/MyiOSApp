import SwiftUI
import EventKit
import WidgetKit

/// The app only exists to ask for calendar access (the widget can't show the
/// permission prompt itself) and to host the widget extension.
struct ContentView: View {
    @State private var status = EKEventStore.authorizationStatus(for: .event)
    private let store = EKEventStore()

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "calendar")
                .font(.system(size: 48))
            Text("Calendar Widget")
                .font(.title2.bold())

            if status == .fullAccess {
                Text("Calendar access granted.\nLong-press your Home Screen, tap +, and add \"Upcoming Events\".")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            } else {
                Text("The widget needs access to your calendar to show events.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                Button("Allow calendar access") {
                    Task {
                        _ = try? await store.requestFullAccessToEvents()
                        status = EKEventStore.authorizationStatus(for: .event)
                        WidgetCenter.shared.reloadAllTimelines()
                    }
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
    }
}
