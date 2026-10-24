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
    @State private var colorTick = 0     // bumped on appear so color changes from Settings show up
    @State private var status = EKEventStore.authorizationStatus(for: .event)
    @State private var scrollY: CGFloat = 0              // how far the list has scrolled
    @State private var insetHeight: CGFloat = 0
    @State private var dayTops: [Date: CGFloat] = [:]    // where each day starts in the list

    // MARK: Data

    private var colors: SharedSettings.ColorSet {
        SharedSettings.isPro ? SharedSettings.colorSettings.resolved(for: scheme) : SharedSettings.ColorSet()
    }
    /// Dark gray like the widget in Dark mode (not black); the system background in Light mode.
    private var pageBackground: Color {
        colors.background?.color ?? (scheme == .dark ? Color(red: 0.11, green: 0.11, blue: 0.118) : Color(.systemBackground))
    }
    private var textColor: Color { colors.text?.color ?? .primary }

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
            // Same title bar as Settings when access is missing, so both screens line up exactly.
            .navigationTitle("Calendar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(status == .fullAccess ? .hidden : .visible, for: .navigationBar)
        }
        .onAppear { colorTick += 1; load() }
        .onReceive(tick) { now = $0 }
        .onReceive(NotificationCenter.default.publisher(for: .weatherUpdated)) { _ in now = Date() }
        .onReceive(NotificationCenter.default.publisher(for: .EKEventStoreChanged)) { _ in load() }
        .onChange(of: scenePhase) { _, phase in if phase == .active { load() } }
    }

    private var unavailable: some View {
        CalendarAccessNeededView(status: status) {
            Task {
                _ = try? await store.requestFullAccessToEvents()
                load()
                SharedSettings.reloadWidgets()
            }
        }
    }

    private var list: some View {
        let cal = Calendar.current
        let all = groups
        return ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if all.first.map({ !cal.isDate($0.day, inSameDayAs: now) }) ?? true {
                        Text(all.isEmpty ? "No upcoming events" : "No more events today")
                            .font(.system(size: 15.5))
                            .foregroundStyle(.secondary)
                            .padding(.bottom, 6)
                    }
                    ForEach(Array(all.enumerated()), id: \.element.day) { index, group in
                        VStack(alignment: .leading, spacing: 0) {
                            if !cal.isDate(group.day, inSameDayAs: now) {
                                if index > 0 {
                                    Rectangle()
                                        .fill(textColor.opacity(0.25))
                                        .frame(height: 1 / displayScale)
                                        .padding(.vertical, 10)
                                }
                                Text(group.day.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))
                                    .font(.system(size: 15.5, weight: .bold))
                                    .padding(.bottom, 3)
                            }
                            ForEach(group.events) { row($0) }
                        }
                        .id(group.day)
                        .background {
                            GeometryReader { geo in
                                Color.clear.preference(key: DayTopKey.self,
                                                       value: [group.day: geo.frame(in: .named("dayStack")).minY])
                            }
                        }
                    }
                }
                .coordinateSpace(name: "dayStack")
                .background {
                    GeometryReader { geo in
                        Color.clear.preference(key: ScrollTopKey.self, value: geo.frame(in: .named("scrollArea")).minY)
                    }
                }
                .onPreferenceChange(DayTopKey.self) { dayTops = $0 }
                .padding(.horizontal, 15)
                .padding(.top, 18)
                .padding(.bottom, 16)
            }
            .coordinateSpace(name: "scrollArea")
            .onPreferenceChange(ScrollTopKey.self) { scrollY = insetHeight - $0 }
            .scrollIndicators(.hidden)
            .foregroundStyle(textColor)
            .background { pageBackground.ignoresSafeArea() }
            .safeAreaInset(edge: .top, spacing: 0) {
                VStack(spacing: 0) {
                    header
                    weekStrip(groups: all) { day in
                        // Jump to that day, or the next day that has events.
                        if let target = all.first(where: { $0.day >= day }) {
                            withAnimation(.easeInOut(duration: 0.35)) { proxy.scrollTo(target.day, anchor: .top) }
                        }
                    }
                }
                .background {
                    GeometryReader { geo in
                        Color.clear.onAppear { insetHeight = geo.size.height }
                            .onChange(of: geo.size.height) { _, h in insetHeight = h }
                    }
                }
            }
            .refreshable { load() }
        }
    }

    // MARK: Week strip

    private let stripDays = 14
    private let stripVisible = 7

    /// How far down the list the reader is, measured in days (fractional), so the strip glides.
    private func dayPosition(_ groups: [(day: Date, events: [AppEvent])]) -> CGFloat {
        let cal = Calendar.current
        let today = cal.startOfDay(for: now)
        let pts = groups.compactMap { g -> (y: CGFloat, d: CGFloat)? in
            guard let y = dayTops[g.day] else { return nil }
            let d = cal.dateComponents([.day], from: today, to: g.day).day ?? 0
            return (y, CGFloat(d))
        }.sorted { $0.y < $1.y }
        guard let first = pts.first else { return 0 }
        let v = scrollY + 4
        if v <= first.y { return first.d == 0 ? 0 : 0 }
        for i in 1..<max(pts.count, 1) where i < pts.count {
            if v < pts[i].y {
                let a = pts[i - 1], b = pts[i]
                let t = (v - a.y) / max(b.y - a.y, 1)
                return a.d + (b.d - a.d) * t
            }
        }
        return pts.last!.d
    }

    private func weekStrip(groups: [(day: Date, events: [AppEvent])], jump: @escaping (Date) -> Void) -> some View {
        let cal = Calendar.current
        let today = cal.startOfDay(for: now)
        let pos = max(0, min(dayPosition(groups), CGFloat(stripDays - 1)))
        let shift = min(pos, CGFloat(stripDays - stripVisible))
        let current = Int(pos.rounded())
        let counts = Dictionary(uniqueKeysWithValues: groups.map { ($0.day, $0.events.count) })

        return GeometryReader { geo in
            let cell = (geo.size.width - 30) / CGFloat(stripVisible)
            HStack(spacing: 0) {
                ForEach(0..<stripDays, id: \.self) { i in
                    let day = cal.date(byAdding: .day, value: i, to: today) ?? today
                    let isToday = i == 0
                    let n = min(counts[day] ?? 0, 3)
                    VStack(spacing: 4) {
                        Text(day.formatted(.dateTime.weekday(.narrow)))
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundStyle(.secondary)
                        ZStack {
                            if isToday { Circle().fill(highlight) }
                            if i == current { Circle().stroke(textColor, lineWidth: 1.5).padding(isToday ? -3 : 0) }
                            Text(day.formatted(.dateTime.day()))
                                .font(.system(size: 15, weight: isToday ? .bold : .regular))
                                .foregroundStyle(isToday ? Color.black : textColor)
                        }
                        .frame(width: 30, height: 30)
                        HStack(spacing: 3) {
                            ForEach(0..<3, id: \.self) { k in
                                Circle().fill(k < n ? textColor.opacity(0.7) : .clear).frame(width: 4, height: 4)
                            }
                        }
                    }
                    .frame(width: cell)
                    .opacity(i < current ? 0.45 : 1)
                    .contentShape(Rectangle())
                    .onTapGesture { jump(day) }
                }
            }
            .offset(x: 15 - shift * cell)
            .frame(width: geo.size.width, alignment: .leading)
            .clipped()
        }
        .frame(height: 78)
        .background(pageBackground)
        .overlay(alignment: .top) { Rectangle().fill(textColor.opacity(0.25)).frame(height: 1 / displayScale) }
        .overlay(alignment: .bottom) { Rectangle().fill(textColor.opacity(0.25)).frame(height: 1 / displayScale) }
    }

    /// Stays at the top while the events scroll underneath.
    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: -5) {
                Text(now.formatted(.dateTime.weekday(.wide)))
                    .font(.system(size: 23, weight: .bold))
                Text(now.formatted(.dateTime.day().month(.wide)))
                    .font(.system(size: 32, weight: .thin))
            }
            Spacer()
            if let snap = SharedSettings.weather, Date().timeIntervalSince(snap.fetched) < 3 * 3600 {
                WeatherIconView(name: snap.iconName, color: textColor, size: 43)
            }
        }
        .padding(.horizontal, 15)
        .padding(.top, 6)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(pageBackground)
    }

    private func clock(_ d: Date) -> String {
        d.formatted(Date.FormatStyle().hour().minute())
    }

    private func row(_ e: AppEvent) -> some View {
        let active = !e.isAllDay && e.start <= now && e.end > now
        return HStack(alignment: .top, spacing: 11) {
            VStack(alignment: .leading, spacing: 0) {
                Text(e.isAllDay ? "All day" : clock(e.start))
                    .font(.system(size: 14.5, weight: .bold))
                Text(e.isAllDay ? " " : clock(e.end))
                    .font(.system(size: 11.5))
            }
            .fontWidth(.condensed)
            .monospacedDigit()
            .frame(width: 44, alignment: .leading)

            VStack(alignment: .leading, spacing: 0) {
                Text(e.title)
                    .font(.system(size: 14.5, weight: .medium))
                    .lineLimit(2)
                Text(e.location ?? " ")
                    .font(.system(size: 11.5))
                    .italic()
                    .lineLimit(1)
                    .opacity(0.85)
            }
        }
        .foregroundStyle(active ? highlight : textColor)
        .padding(.vertical, 4)
    }
}

/// Two tabs: Calendar and Settings. Also asks for permissions the first time the app opens.
struct RootView: View {
    private let store = EKEventStore()
    @EnvironmentObject private var location: LocationAccess

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

/// The "Calendar Access Needed" screen, shared by the Calendar and Settings tabs so they look identical.
struct CalendarAccessNeededView: View {
    let status: EKAuthorizationStatus
    let onAllow: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label("Calendar Access Needed", systemImage: "calendar.badge.exclamationmark")
        } description: {
            Text("Minimal needs access to your calendar to show your events.")
        } actions: {
            if status == .denied || status == .restricted {
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                .buttonStyle(.borderedProminent)
            } else {
                Button("Allow Calendar Access", action: onAllow)
                    .buttonStyle(.borderedProminent)
            }
        }
    }
}

private struct DayTopKey: PreferenceKey {
    static var defaultValue: [Date: CGFloat] = [:]
    static func reduce(value: inout [Date: CGFloat], nextValue: () -> [Date: CGFloat]) {
        value.merge(nextValue()) { $1 }
    }
}

private struct ScrollTopKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}
