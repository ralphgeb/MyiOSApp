import SwiftUI
import EventKit

/// An event as the Calendar tab needs it.
struct AppEvent: Identifiable {
    let id: String
    let title: String
    let start: Date
    let end: Date
    let isAllDay: Bool
    let location: String?
}

/// The Calendar tab: the same look as the large widget, but it keeps going down the page.
struct CalendarTabView: View {
    private let store = EKEventStore()
    private let daysToShow = 14
    private let tick = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.colorScheme) private var scheme
    @Environment(\.displayScale) private var displayScale
    @State private var events: [AppEvent] = []
    @State private var now = Date()
    @State private var status = EKEventStore.authorizationStatus(for: .event)

    // MARK: Data

    private var highlight: Color {
        guard SharedSettings.isPro else { return .orange }
        return SharedSettings.colorSettings.resolved(for: scheme).highlight?.color ?? .orange
    }

    /// Finished events are hidden, so the first row is always what's on now or next.
    private var groups: [(day: Date, events: [AppEvent])] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: now)
        let upcoming = events.filter { $0.end > now }
        let byDay = Dictionary(grouping: upcoming) { cal.startOfDay(for: max($0.start, today)) }
        return byDay.keys.sorted().map { (day: $0, events: byDay[$0]!.sorted { $0.start < $1.start }) }
    }

    private func load() {
        status = EKEventStore.authorizationStatus(for: .event)
        guard status == .fullAccess else { events = []; return }
        let cal = Calendar.current
        let start = cal.startOfDay(for: .now)
        guard let end = cal.date(byAdding: .day, value: daysToShow, to: start) else { return }

        // Same rules as the widget: only chosen calendars once unlocked.
        let hidden = SharedSettings.isPro ? SharedSettings.hiddenCalendarIDs : []
        let selected = store.calendars(for: .event).filter { !hidden.contains($0.calendarIdentifier) }
        guard !selected.isEmpty else { events = []; return }
        let showAllDay = !SharedSettings.isPro || SharedSettings.showAllDay

        events = store.events(matching: store.predicateForEvents(withStart: start, end: end, calendars: selected))
            .filter { showAllDay || !$0.isAllDay }
            .sorted { $0.startDate < $1.startDate }
            .map { AppEvent(id: ($0.eventIdentifier ?? UUID().uuidString) + "\($0.startDate.timeIntervalSince1970)",
                            title: $0.title ?? "Untitled",
                            start: $0.startDate, end: $0.endDate, isAllDay: $0.isAllDay,
                            location: ($0.location?.isEmpty == false) ? $0.location : nil) }
        now = Date()
    }

    // MARK: Body

    var body: some View {
        NavigationStack {
            Group {
                if status == .fullAccess { list } else { unavailable }
            }
            .toolbar(.hidden, for: .navigationBar)
        }
        .onAppear(perform: load)
        .onReceive(tick) { now = $0 }
        .onReceive(NotificationCenter.default.publisher(for: .EKEventStoreChanged)) { _ in load() }
        .onChange(of: scenePhase) { _, phase in if phase == .active { load() } }
    }

    private var unavailable: some View {
        ContentUnavailableView {
            Label("Calendar Access Needed", systemImage: "calendar.badge.exclamationmark")
        } description: {
            Text("Allow calendar access to see your events here.")
        } actions: {
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private var list: some View {
        let cal = Calendar.current
        let all = groups
        return ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                if all.first.map({ !cal.isDate($0.day, inSameDayAs: now) }) ?? true {
                    Text(all.isEmpty ? "No upcoming events" : "No more events today")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .padding(.bottom, 8)
                }
                ForEach(Array(all.enumerated()), id: \.element.day) { index, group in
                    if !cal.isDate(group.day, inSameDayAs: now) {
                        if index > 0 {
                            Rectangle()
                                .fill(Color.primary.opacity(0.25))
                                .frame(height: 1 / displayScale)
                                .padding(.vertical, 14)
                        }
                        Text(group.day.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))
                            .font(.title3.bold())
                            .padding(.bottom, 4)
                    }
                    ForEach(group.events) { row($0) }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 4)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .safeAreaInset(edge: .top, spacing: 0) { header }
        .refreshable { load() }
    }

    /// Stays at the top while the events scroll underneath.
    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: -7) {
                Text(now.formatted(.dateTime.weekday(.wide)))
                    .font(.system(size: 30, weight: .bold))
                Text(now.formatted(.dateTime.day().month(.wide)))
                    .font(.system(size: 42, weight: .thin))
            }
            Spacer()
            if let snap = SharedSettings.weather, Date().timeIntervalSince(snap.fetched) < 3 * 3600 {
                WeatherIconView(name: snap.iconName, color: .primary, size: 56)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.bar)
    }

    private func clock(_ d: Date) -> String {
        d.formatted(Date.FormatStyle().hour().minute())
    }

    private func row(_ e: AppEvent) -> some View {
        let active = !e.isAllDay && e.start <= now && e.end > now
        return HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 0) {
                Text(e.isAllDay ? "All day" : clock(e.start))
                    .font(.system(size: 18, weight: .bold))
                Text(e.isAllDay ? " " : clock(e.end))
                    .font(.system(size: 15))
            }
            .fontWidth(.condensed)
            .monospacedDigit()
            .frame(width: 56, alignment: .leading)

            VStack(alignment: .leading, spacing: 0) {
                Text(e.title)
                    .font(.system(size: 18, weight: .medium))
                    .lineLimit(2)
                Text(e.location ?? " ")
                    .font(.system(size: 15))
                    .italic()
                    .lineLimit(1)
                    .opacity(0.85)
            }
        }
        .foregroundStyle(active ? highlight : Color.primary)
        .padding(.vertical, 6)
    }
}

/// Two tabs: Calendar and Settings. Also asks for permissions the first time the app opens.
struct RootView: View {
    private let store = EKEventStore()
    @StateObject private var location = LocationAccess()

    var body: some View {
        TabView {
            CalendarTabView()
                .tabItem { Label("Calendar", systemImage: "calendar") }
            ContentView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
        }
        .task { await askForPermissions() }
    }

    /// First launch: calendar access first, then location (one prompt at a time).
    private func askForPermissions() async {
        if EKEventStore.authorizationStatus(for: .event) == .notDetermined {
            _ = try? await store.requestFullAccessToEvents()
            SharedSettings.reloadWidgets()
        }
        if location.status == .notDetermined {
            location.request()
        }
    }
}
