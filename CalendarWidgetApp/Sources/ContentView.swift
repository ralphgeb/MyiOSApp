import SwiftUI
import EventKit
import WidgetKit

/// Settings page: choose which calendars the widget shows.
struct ContentView: View {
    private let store = EKEventStore()

    @State private var status = EKEventStore.authorizationStatus(for: .event)
    @State private var calendars: [EKCalendar] = []
    @State private var hidden = SharedSettings.hiddenCalendarIDs
    @State private var daysAhead = SharedSettings.daysAhead
    @State private var showAllDay = SharedSettings.showAllDay

    var body: some View {
        NavigationStack {
            Group {
                if status == .fullAccess {
                    settingsForm
                } else {
                    accessNeeded
                }
            }
            .navigationTitle("Calendar Widget")
            .navigationBarTitleDisplayMode(.inline)   // compact title instead of the large one
            .onAppear(perform: reload)
        }
    }

    // MARK: Screens

    private var settingsForm: some View {
        Form {
            calendarSections
            optionsSection
            Section {
            } footer: {
                Text("To add the widget, touch and hold your Home Screen, tap the add button, then choose Upcoming Events.")
            }
        }
    }

    /// Standard empty state for a missing permission.
    private var accessNeeded: some View {
        ContentUnavailableView {
            Label("Calendar Access Needed", systemImage: "calendar.badge.exclamationmark")
        } description: {
            Text("The widget needs access to your calendar to show your events.")
        } actions: {
            if status == .denied || status == .restricted {
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                .buttonStyle(.borderedProminent)
            } else {
                Button("Allow Calendar Access") {
                    Task {
                        _ = try? await store.requestFullAccessToEvents()
                        reload()
                        pushToWidget()
                    }
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    // MARK: Sections

    /// One section per account (iCloud, Gmail, Other...), a toggle per calendar.
    private var calendarSections: some View {
        ForEach(groupedCalendars, id: \.title) { group in
            Section(group.title) {
                ForEach(group.calendars, id: \.calendarIdentifier) { cal in
                    Toggle(isOn: binding(for: cal)) {
                        Label {
                            Text(cal.title)
                        } icon: {
                            Image(systemName: "circle.fill")
                                .foregroundStyle(Color(cgColor: cal.cgColor))
                                .imageScale(.small)
                        }
                    }
                }
            }
        }
    }

    private var optionsSection: some View {
        Section {
            Stepper("Days Shown: \(daysAhead)", value: $daysAhead, in: 1...7)
                .onChange(of: daysAhead) { _, new in
                    SharedSettings.daysAhead = new
                    pushToWidget()
                }
            Toggle("Show All-Day Events", isOn: $showAllDay)
                .onChange(of: showAllDay) { _, new in
                    SharedSettings.showAllDay = new
                    pushToWidget()
                }
        } header: {
            Text("Options")
        } footer: {
            Text("Days shown includes today.")
        }
    }

    // MARK: Data

    private var groupedCalendars: [(title: String, calendars: [EKCalendar])] {
        Dictionary(grouping: calendars) { $0.source?.title ?? "Other" }
            .map { (title: $0.key, calendars: $0.value.sorted { $0.title < $1.title }) }
            .sorted { $0.title < $1.title }
    }

    private func binding(for cal: EKCalendar) -> Binding<Bool> {
        Binding(
            get: { !hidden.contains(cal.calendarIdentifier) },
            set: { isOn in
                if isOn { hidden.remove(cal.calendarIdentifier) }
                else { hidden.insert(cal.calendarIdentifier) }
                SharedSettings.hiddenCalendarIDs = hidden
                pushToWidget()
            }
        )
    }

    private func reload() {
        status = EKEventStore.authorizationStatus(for: .event)
        if status == .fullAccess {
            calendars = store.calendars(for: .event)
        }
    }

    private func pushToWidget() {
        WidgetCenter.shared.reloadAllTimelines()
    }
}
