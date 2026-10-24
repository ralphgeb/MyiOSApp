import SwiftUI
import EventKit
import CoreLocation
import WidgetKit
import WeatherKit

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
    @EnvironmentObject private var location: LocationAccess
    @StateObject private var purchase = Store()
    @State private var showPaywall = false
    @State private var diagnosticsTick = 0

    var body: some View {
        NavigationStack {
            Group {
                if status == .fullAccess {
                    settingsForm
                } else {
                    accessNeeded
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)   // compact title instead of the large one
            .onAppear(perform: reload)
            .sheet(isPresented: $showPaywall) { PaywallView(store: purchase) }
        }
    }

    // MARK: Screens

    private var settingsForm: some View {
        Form {
            unlockSection
            calendarsSection
            customisationSection
            optionsSection
            weatherSection
            diagnosticsSection
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

    /// One button that opens the unlock window (covers every widget and setting).
    private var unlockSection: some View {
        Section {
            if purchase.isPro {
                Label("All widgets and settings unlocked", systemImage: "checkmark.seal.fill")
                    .foregroundStyle(.green)
            } else {
                Button { showPaywall = true } label: {
                    HStack {
                        Label("Unlock All Widgets", systemImage: "lock.open")
                        Spacer()
                        Text(purchase.product?.displayPrice ?? "£1.99").foregroundStyle(.secondary)
                    }
                }
            }
        } footer: {
            if !purchase.isPro { Text("One payment unlocks the medium, extra large and Lock Screen widgets and all settings.") }
        }
    }

    /// One row that opens the list of calendar switches.
    private var calendarsSection: some View {
        Section {
            NavigationLink {
                CalendarTogglesView(calendars: calendars, hidden: $hidden,
                                    isUnlocked: purchase.isPro,
                                    onLocked: { showPaywall = true },
                                    onChange: {
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

    /// While locked, taps on a row open the upgrade window instead.
    private func locked<V: View>(_ view: V) -> some View {
        view
            .allowsHitTesting(purchase.isPro)
            .overlay {
                if !purchase.isPro {
                    Color.clear.contentShape(Rectangle()).onTapGesture { showPaywall = true }
                }
            }
    }

    private var customisationSection: some View {
        Section {
            locked(ColorPicker("Background Color", selection: backgroundBinding, supportsOpacity: false))
            locked(ColorPicker("Text Color", selection: textBinding, supportsOpacity: false))
            locked(ColorPicker("Highlight Color", selection: highlightBinding, supportsOpacity: false))
            locked(Toggle("Same Colors in Light and Dark", isOn: appearanceBinding)
                .disabled(!hasCustomColors))
            locked(Button("Reset Colors", role: .destructive) {
                SharedSettings.resetColors()
                syncColorState()
                colorRefresh += 1
                scheduleWidgetReload()
            })
        } header: {
            HStack {
                Text("Widget Customisation")
                if !purchase.isPro { Image(systemName: "lock.fill").imageScale(.small) }
            }
        } footer: {
            Text("Pick solid colors for the widget. Turn the switch on to use them in Light and Dark mode. Reset turns it off.")
        }
        .id(colorRefresh)
    }

    private var optionsSection: some View {
        Section {
            locked(Stepper("Days Shown: \(purchase.isPro ? daysAhead : SharedSettings.freeDays)", value: $daysAhead, in: 1...7)
                .onChange(of: daysAhead) { _, new in
                    SharedSettings.daysAhead = new
                    scheduleWidgetReload()
                })
            locked(Toggle("Show All-Day Events", isOn: $showAllDay)
                .onChange(of: showAllDay) { _, new in
                    SharedSettings.showAllDay = new
                    scheduleWidgetReload()
                })
        } header: {
            HStack {
                Text("Options")
                if !purchase.isPro { Image(systemName: "lock.fill").imageScale(.small) }
            }
        } footer: {
            Text("Days shown includes today.")
        }
    }

    /// Testing aid: shows what the weather lookup and the widget arrows last did.
    private var diagnosticsSection: some View {
        Section {
            if let error = SharedSettings.weatherError {
                Text("Weather problem: \(error)").font(.footnote).foregroundStyle(.red)
            } else if let snap = SharedSettings.weather {
                Text("Weather OK, updated \(snap.fetched.formatted(date: .omitted, time: .shortened))")
                    .font(.footnote).foregroundStyle(.secondary)
            } else {
                Text("Weather: no data yet").font(.footnote).foregroundStyle(.secondary)
            }
            Text("Last arrow tap: \(SharedSettings.pagingLog ?? "none yet")")
                .font(.footnote).foregroundStyle(.secondary)
            Button("Retry Weather Now") {
                location.refreshWeather()
                diagnosticsTick += 1
            }
        } header: {
            Text("Diagnostics")
        }
        .id(diagnosticsTick)
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
            AppleWeatherAttribution()
        } header: {
            Text("Weather")
        } footer: {
            Text("Shows the weather where you are, as an icon at the top of the widget. Choose \"Allow While Using App\" (not \"Allow Once\"). It updates once an hour.")
        }
    }

    // MARK: Colour bindings (read and write the shared settings directly)

    private var backgroundBinding: Binding<Color> {
        Binding(
            get: { SharedSettings.editableColors(for: scheme).background?.color ?? (scheme == .dark ? Color(white: 0.11) : .white) },
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
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }
            SharedSettings.reloadWidgets()
        }
    }
}

/// The "Calendars" screen: every calendar with its own on/off switch, grouped by account.
struct CalendarTogglesView: View {
    let calendars: [EKCalendar]
    @Binding var hidden: Set<String>
    let isUnlocked: Bool
    let onLocked: () -> Void
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
                        // Locked: tapping a calendar opens the unlock window instead of switching it.
                        .allowsHitTesting(isUnlocked)
                        .overlay {
                            if !isUnlocked {
                                Color.clear.contentShape(Rectangle()).onTapGesture(perform: onLocked)
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

    private var force = false

    func request() {
        manager.requestWhenInUseAuthorization()
    }

    /// Look up the weather again right now, ignoring the 10-minute rule.
    func refreshWeather() {
        force = true
        manager.requestLocation()
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        status = manager.authorizationStatus
        if status == .authorizedWhenInUse || status == .authorizedAlways {
            manager.requestLocation()
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }
        SharedSettings.lastCoordinate = SharedSettings.Coordinate(lat: loc.coordinate.latitude,
                                                                  lon: loc.coordinate.longitude)
        // Fetch the weather right away (instead of waiting for the widget's own refresh) so the
        // icon appears as soon as location is allowed. Skipped if the saved weather is under 10 minutes old.
        if !force, let saved = SharedSettings.weather, Date().timeIntervalSince(saved.fetched) < 10 * 60 { return }
        force = false
        Task {
            if let fresh = await WeatherFetcher.fetch(lat: loc.coordinate.latitude, lon: loc.coordinate.longitude) {
                SharedSettings.weather = fresh
                SharedSettings.reloadWidgets()
                NotificationCenter.default.post(name: .weatherUpdated, object: nil)
            }
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {}
}

extension Notification.Name {
    static let weatherUpdated = Notification.Name("weatherUpdated")
}

/// Apple requires apps that show WeatherKit data to show the "Apple Weather" mark and link to its legal page.
struct AppleWeatherAttribution: View {
    @Environment(\.colorScheme) private var scheme
    @State private var attribution: WeatherAttribution?

    private static let fallbackURL = URL(string: "https://weatherkit.apple.com/legal-attribution.html")!

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let url = scheme == .dark ? attribution?.combinedMarkDarkURL : attribution?.combinedMarkLightURL {
                AsyncImage(url: url) { image in
                    image.resizable().scaledToFit()
                } placeholder: {
                    Text("Apple Weather")
                }
                .frame(height: 16)
            } else {
                Text("Apple Weather")
            }
            Link("Weather data and legal information", destination: attribution?.legalPageURL ?? Self.fallbackURL)
                .font(.footnote)
        }
        .task {
            attribution = try? await WeatherService.shared.attribution
        }
    }
}
