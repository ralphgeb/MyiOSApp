import SwiftUI
import EventKit
import CoreLocation
import WidgetKit

/// Settings page: choose which calendars the widget shows and how it looks.
struct ContentView: View {
    private let store = EKEventStore()

    @Environment(\.colorScheme) private var scheme
    @State private var status = EKEventStore.authorizationStatus(for: .event)
    @State private var calendars: [EKCalendar] = []
    @State private var hidden = SharedSettings.hiddenCalendarIDs
    @State private var daysAhead = SharedSettings.daysAhead
    @State private var showAllDay = SharedSettings.showAllDay
    @State private var ignoreAppearance = SharedSettings.ignoreAppearance
    @State private var hasCustomColors = SharedSettings.hasCustomColors
    @State private var colorRefresh = 0          // bumped to redraw the colour pickers
    @State private var pendingReload: Task<Void, Never>?
    @StateObject private var location = LocationAccess()

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
            calendarsSection
            customisationSection
            optionsSection
            weatherSection
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
                        scheduleWidgetReload()
                    }
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    // MARK: Sections

    /// One row that opens the list of calendar switches.
    private var calendarsSection: some View {
        Section {
            NavigationLink {
                CalendarTogglesView(calendars: calendars, hidden: $hidden, onChange: {
                    SharedSettings.hiddenCalendarIDs = hidden
                    scheduleWidgetReload()
                })
            } label: {
                HStack {
                    Label("Calendars", systemImage: "folder")
                    Spacer()
                    Text("\(calendars.filter { !hidden.contains($0.calendarIdentifier) }.count) of \(calendars.count) on")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var customisationSection: some View {
        Section {
            ColorPicker("Background Color", selection: backgroundBinding, supportsOpacity: true)
            ColorPicker("Text Color", selection: textBinding, supportsOpacity: false)
            ColorPicker("Highlight Color", selection: highlightBinding, supportsOpacity: false)
            Toggle("Same Colors in Light and Dark", isOn: appearanceBinding)
                .disabled(!hasCustomColors)
            Button("Reset Colors", role: .destructive) {
                SharedSettings.resetColors()
                syncColorState()
                colorRefresh += 1
                scheduleWidgetReload()
            }
        } header: {
            Text("Widget Customisation")
        } footer: {
            Text("The background is transparent by default. The highlight color marks the event happening now. Lower the opacity in the color picker to make it see-through. Once you change a color, turn on the switch to use your colors in both Light and Dark mode. When it's off, each mode keeps its own colors. Reset Colors turns it off again.")
        }
        .id(colorRefresh)
    }

    private var optionsSection: some View {
        Section {
            Stepper("Days Shown: \(daysAhead)", value: $daysAhead, in: 1...7)
                .onChange(of: daysAhead) { _, new in
                    SharedSettings.daysAhead = new
                    scheduleWidgetReload()
                }
            Toggle("Show All-Day Events", isOn: $showAllDay)
                .onChange(of: showAllDay) { _, new in
                    SharedSettings.showAllDay = new
                    scheduleWidgetReload()
                }
        } header: {
            Text("Options")
        } footer: {
            Text("Days shown includes today.")
        }
    }

    /// The weather icon in the widget needs "While Using" location access.
    private var weatherSection: some View {
        Section {
            switch location.status {
            case .authorizedWhenInUse, .authorizedAlways:
                Label("Weather is on", systemImage: "checkmark.circle")
                    .foregroundStyle(.secondary)
            case .denied, .restricted:
                Button("Open Settings to Allow Location") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
            default:
                Button("Allow Location for Weather") { location.request() }
            }
        } header: {
            Text("Weather")
        } footer: {
            Text("Shows the weather where you are, as an icon at the top of the widget. It updates once an hour.")
        }
    }

    // MARK: Colour bindings (read and write the shared settings directly)

    private var backgroundBinding: Binding<Color> {
        Binding(
            get: { SharedSettings.editableColors(for: scheme).background?.color ?? .clear },
            set: { new in
                SharedSettings.updateColors(for: scheme) { $0.background = RGBA(new) }
                syncColorState()
                scheduleWidgetReload()
            }
        )
    }

    private var textBinding: Binding<Color> {
        Binding(
            get: { SharedSettings.editableColors(for: scheme).text?.color ?? (scheme == .dark ? .white : .black) },
            set: { new in
                SharedSettings.updateColors(for: scheme) { $0.text = RGBA(new) }
                syncColorState()
                scheduleWidgetReload()
            }
        )
    }

    private var highlightBinding: Binding<Color> {
        Binding(
            get: { SharedSettings.editableColors(for: scheme).highlight?.color ?? .orange },
            set: { new in
                SharedSettings.updateColors(for: scheme) { $0.highlight = RGBA(new) }
                syncColorState()
                scheduleWidgetReload()
            }
        )
    }

    private var appearanceBinding: Binding<Bool> {
        Binding(
            get: { ignoreAppearance },
            set: { on in
                SharedSettings.setIgnoreAppearance(on, currentScheme: scheme)
                syncColorState()
                colorRefresh += 1
                scheduleWidgetReload()
            }
        )
    }

    private func syncColorState() {
        ignoreAppearance = SharedSettings.ignoreAppearance
        hasCustomColors = SharedSettings.hasCustomColors
    }

    // MARK: Data

    private func reload() {
        status = EKEventStore.authorizationStatus(for: .event)
        if status == .fullAccess {
            calendars = store.calendars(for: .event)
        }
        syncColorState()
    }

    /// Battery: wait for changes to settle (a colour picker sends many changes while you drag)
    /// and refresh only this widget, once.
    private func scheduleWidgetReload() {
        pendingReload?.cancel()
        pendingReload = Task {
            try? await Task.sleep(nanoseconds: 700_000_000)
            guard !Task.isCancelled else { return }
            WidgetCenter.shared.reloadTimelines(ofKind: SharedSettings.widgetKind)
        }
    }
}

/// The "Calendars" screen: every calendar with its own on/off switch, grouped by account.
struct CalendarTogglesView: View {
    let calendars: [EKCalendar]
    @Binding var hidden: Set<String>
    let onChange: () -> Void

    private var grouped: [(title: String, calendars: [EKCalendar])] {
        Dictionary(grouping: calendars) { $0.source?.title ?? "Other" }
            .map { (title: $0.key, calendars: $0.value.sorted { $0.title < $1.title }) }
            .sorted { $0.title < $1.title }
    }

    var body: some View {
        Form {
            ForEach(grouped, id: \.title) { group in
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
        .navigationTitle("Calendars")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func binding(for cal: EKCalendar) -> Binding<Bool> {
        Binding(
            get: { !hidden.contains(cal.calendarIdentifier) },
            set: { isOn in
                if isOn { hidden.remove(cal.calendarIdentifier) }
                else { hidden.insert(cal.calendarIdentifier) }
                onChange()
            }
        )
    }
}

/// Watches the location permission and remembers where the user is,
/// so the widget can look up the weather.
final class LocationAccess: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var status: CLAuthorizationStatus
    private let manager = CLLocationManager()

    override init() {
        status = .notDetermined
        super.init()
        status = manager.authorizationStatus
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
        if status == .authorizedWhenInUse || status == .authorizedAlways {
            manager.requestLocation()
        }
    }

    func request() {
        manager.requestWhenInUseAuthorization()
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        status = manager.authorizationStatus
        if status == .authorizedWhenInUse || status == .authorizedAlways {
            manager.requestLocation()
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }
        let previous = SharedSettings.lastCoordinate
        SharedSettings.lastCoordinate = SharedSettings.Coordinate(lat: loc.coordinate.latitude,
                                                                  lon: loc.coordinate.longitude)
        // Battery: only refresh the widget if this is the first fix or you've moved over 5 km.
        let moved = previous.map {
            CLLocation(latitude: $0.lat, longitude: $0.lon).distance(from: loc) > 5000
        } ?? true
        if moved {
            WidgetCenter.shared.reloadTimelines(ofKind: SharedSettings.widgetKind)
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {}
}
