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
    @State private var weatherFetched: Date? = SharedSettings.forecast?.fetched
    @State private var ignoreAppearance = SharedSettings.ignoreAppearance
    @State private var hasCustomColors = SharedSettings.hasCustomColors
    @State private var colorRefresh = 0          // bumped to redraw the color pickers
    @State private var mode = SharedSettings.appearanceMode
    @State private var paletteTick = 0           // bumped whenever a color changes, so the page redraws
    @State private var pendingReload: Task<Void, Never>?
    @EnvironmentObject private var location: LocationAccess
    @StateObject private var purchase = Store()
    @State private var showPaywall = false
    @State private var resetFlash = false
    @State private var resetTick = 0

    private var theme: AppTheme {
        _ = paletteTick
        return AppTheme(scheme: scheme)
    }

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
            .toolbarColorScheme(theme.barScheme, for: .navigationBar)
            .onAppear(perform: reload)
            .onReceive(NotificationCenter.default.publisher(for: .weatherUpdated)) { _ in
                weatherFetched = SharedSettings.forecast?.fetched
            }
            .sheet(isPresented: $showPaywall) { PaywallView(store: purchase) }
        }
    }

    // MARK: Screens

    private var settingsForm: some View {
        Form {
            unlockSection.listRowBackground(theme.card)
            calendarsSection.listRowBackground(theme.card)
            modeSection.listRowBackground(theme.card)
            customizationSection.listRowBackground(theme.card)
            optionsSection.listRowBackground(theme.card)
            weatherSection.listRowBackground(theme.card)
            Section {
            } footer: {
                VStack(alignment: .leading, spacing: 8) {
                    Text("To add the widget, touch and hold your Home Screen, tap the add button, then choose Upcoming Events.")
                    if let d = weatherFetched {
                        Text("Weather last requested from Apple Weather on \(d.formatted(.dateTime.day().month(.abbreviated).hour().minute())).")
                    } else {
                        Text("Weather hasn't been requested from Apple Weather yet.")
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(theme.background.ignoresSafeArea())
        .foregroundStyle(theme.ink)
        .tint(theme.ink)
        .animation(nil, value: paletteTick)     // colors change instantly, no fade
    }

    /// Standard empty state for a missing permission.
    private var accessNeeded: some View {
        CalendarAccessNeededView(status: status) {
            Task {
                _ = try? await store.requestFullAccessToEvents()
                reload()
                scheduleWidgetReload()
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

    /// Automatic follows the iPhone; Light or Dark force one look in the app (and in custom-colored widgets).
    private var modeSection: some View {
        Section {
            Picker("Mode", selection: $mode) {
                ForEach(SharedSettings.AppearanceMode.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
            .onChange(of: mode) { _, new in
                SharedSettings.appearanceMode = new
                syncColorState()
                SharedSettings.reloadWidgets()
            }
        } header: {
            Text("Light and Dark")
        } footer: {
            Text("Automatic follows your iPhone's Light or Dark setting. Widgets with your own colors follow it too; the original look follows the iPhone.")
        }
    }

    private var customizationSection: some View {
        Section {
            locked(presetsRow)
            locked(ColorPicker("Background Color", selection: backgroundBinding, supportsOpacity: false))
            locked(ColorPicker("Text Color", selection: textBinding, supportsOpacity: false))
            locked(ColorPicker("Highlight Color", selection: highlightBinding, supportsOpacity: false))
            locked(ColorPicker("Highlighted Date Text", selection: highlightTextBinding, supportsOpacity: false))
            locked(ColorPicker("Cards", selection: cardBinding, supportsOpacity: false))
            preview
            locked(Toggle("Same Colors in Light and Dark", isOn: appearanceBinding)
                .tint(theme.accent)
                .disabled(!hasCustomColors))
            locked(Button {
                SharedSettings.resetColors()
                syncColorState()
                colorRefresh += 1
                scheduleWidgetReload()
                // Visible confirmation: the label turns into a green tick for a moment.
                resetTick += 1
                withAnimation { resetFlash = true }
                Task {
                    try? await Task.sleep(nanoseconds: 1_500_000_000)
                    withAnimation { resetFlash = false }
                }
            } label: {
                if resetFlash {
                    Label("Colors reset", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else {
                    Text("Reset Colors to Default").foregroundStyle(.red)
                }
            }
            .sensoryFeedback(.success, trigger: resetTick))
        } header: {
            HStack {
                Text("Appearance")
                if !purchase.isPro { Image(systemName: "lock.fill").imageScale(.small) }
            }
        } footer: {
            Text("Pick a look or choose your own colors. They apply to the widgets and the Calendar tab. Turn the switch on to use the same colors in Light and Dark mode. Reset goes back to the original.")
        }
        .id(colorRefresh)
    }

    /// Ready-made looks, same set as the sister app.
    private var presetsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 14) {
                ForEach(LookPreset.all) { p in
                    let c = scheme == .dark ? p.dark : p.light
                    let selected = SharedSettings.presetID == p.id
                    Button {
                        SharedSettings.applyPreset(id: p.id, light: p.lightSet, dark: p.darkSet)
                        syncColorState()
                        colorRefresh += 1
                        // Refresh the widgets right away (no wait) so they switch as fast as iOS allows.
                        pendingReload?.cancel()
                        SharedSettings.reloadWidgets()
                    } label: {
                        VStack(spacing: 6) {
                            ZStack {
                                Circle().fill(c.background.color)
                                Circle().inset(by: 7).trim(from: 0, to: 0.72)
                                    .stroke(c.ink.color, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                                    .rotationEffect(.degrees(-90))
                                Circle().fill(p.accent.color).frame(width: 9, height: 9)
                            }
                            .frame(width: 52, height: 52)
                            .overlay(Circle().stroke(selected ? theme.accent : theme.ink.opacity(0.12),
                                                     lineWidth: selected ? 2 : 1))
                            Text(p.name)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(theme.ink.opacity(0.5))
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 6)
        }
    }

    /// A small sample of the highlighted date, so changes are easy to judge.
    private var preview: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().fill(theme.accent)
                Text(Date().formatted(.dateTime.day()))
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(theme.accentText)
            }
            .frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 0) {
                Text(Date().formatted(.dateTime.weekday(.wide)))
                    .font(.system(size: 17, weight: .bold))
                Text(Date().formatted(.dateTime.day().month(.wide)))
                    .font(.system(size: 17, weight: .thin))
            }
            Spacer()
            Text("PREVIEW")
                .font(.system(size: 11, weight: .semibold))
                .tracking(1.1)
                .foregroundStyle(theme.ink.opacity(0.5))
        }
        .padding(.vertical, 4)
    }

    private var cardBinding: Binding<Color> {
        Binding(
            get: { theme.card },
            set: { new in
                SharedSettings.updateColors(for: scheme) { $0.card = RGBA(new) }
                syncColorState()
            }
        )
    }

    private var optionsSection: some View {
        Section {
            locked(Stepper("Days Shown: \(purchase.isPro ? daysAhead : SharedSettings.freeDays)", value: $daysAhead, in: 1...7)
                .onChange(of: daysAhead) { _, new in
                    SharedSettings.daysAhead = new
                    scheduleWidgetReload()
                })
            locked(Toggle("Show All-Day Events", isOn: $showAllDay)
                .tint(theme.accent)
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
            Text("Shows the weather where you are, as an icon at the top of the widget. Choose \"Allow While Using App\" (not \"Allow Once\"). It refreshes a few times a day.")
        }
    }

    // MARK: Color bindings (read and write the shared settings directly)

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

    private var highlightTextBinding: Binding<Color> {
        Binding(
            get: { SharedSettings.editableColors(for: scheme).highlightText?.color ?? .black },
            set: { new in
                SharedSettings.updateColors(for: scheme) { $0.highlightText = RGBA(new) }
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
        paletteTick += 1
        NotificationCenter.default.post(name: .colorsChanged, object: nil)
    }

    // MARK: Data

    private func reload() {
        status = EKEventStore.authorizationStatus(for: .event)
        if status == .fullAccess {
            calendars = store.calendars(for: .event)
        }
        weatherFetched = SharedSettings.forecast?.fetched
        syncColorState()
    }

    /// Battery: wait for changes to settle (a color picker sends many changes while you drag)
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
    @Environment(\.colorScheme) private var scheme

    private var theme: AppTheme { AppTheme(scheme: scheme) }

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
                        .tint(theme.accent)
                        // Locked: tapping a calendar opens the unlock window instead of switching it.
                        .allowsHitTesting(isUnlocked)
                        .overlay {
                            if !isUnlocked {
                                Color.clear.contentShape(Rectangle()).onTapGesture(perform: onLocked)
                            }
                        }
                    }
                }
                .listRowBackground(theme.card)
            }
        }
        .scrollContentBackground(.hidden)
        .background(theme.background.ignoresSafeArea())
        .foregroundStyle(theme.ink)
        .tint(theme.ink)
        .toolbarColorScheme(theme.barScheme, for: .navigationBar)
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
        SharedSettings.lastCoordinate = SharedSettings.Coordinate(lat: loc.coordinate.latitude,
                                                                  lon: loc.coordinate.longitude)
        // Fetch the 24-hour forecast right away so the icon appears as soon as location is allowed,
        // but only if the saved one is missing, running out, or for a different place.
        let lat = loc.coordinate.latitude, lon = loc.coordinate.longitude
        guard SharedSettings.weatherNeedsRefresh(lat: lat, lon: lon) else { return }
        Task {
            if let fresh = await WeatherFetcher.fetch(lat: lat, lon: lon) {
                SharedSettings.forecast = fresh
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
