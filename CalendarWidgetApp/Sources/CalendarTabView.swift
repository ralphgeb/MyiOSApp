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
    private let tick = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.colorScheme) private var scheme
    @Environment(\.displayScale) private var displayScale
    @State private var events: [AppEvent] = []
    @State private var now = Date()
    @State private var colorTick = 0     // bumped on appear so color changes from Settings show up
    @State private var status = EKEventStore.authorizationStatus(for: .event)
    @State private var scrollY: CGFloat = 0              // how far the list has scrolled
    @State private var dateHeaderHeight: CGFloat = 70
    @State private var restTop: CGFloat?
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

    /// Number inside the highlighted date's circle.
    private var highlightedDateText: Color {
        guard SharedSettings.isPro else { return .black }
        return SharedSettings.colorSettings.resolved(for: scheme).highlightText?.color ?? .black
    }

    /// Finished events are hidden, so the first row is always what's on now or next.
    private var groups: [(day: Date, events: [AppEvent])] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: now)
        let limit = Calendar.current.date(byAdding: .day, value: 1, to: lastListDay) ?? .distantFuture
        let upcoming = events.filter { $0.end > now && $0.start < limit }
        let byDay = Dictionary(grouping: upcoming) { cal.startOfDay(for: max($0.start, today)) }
        return byDay.keys.sorted().map { (day: $0, events: byDay[$0]!.sorted { $0.start < $1.start }) }
    }

    private func load() {
        status = EKEventStore.authorizationStatus(for: .event)
        guard status == .fullAccess else { events = []; return }
        store.refreshSourcesIfNecessary()
        let cal = Calendar.current
        let start = gridStart
        guard let end = cal.date(byAdding: .day, value: 1, to: lastListDay) else { return }

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
        .onReceive(NotificationCenter.default.publisher(for: .colorsChanged)) { _ in colorTick += 1 }
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
                    Color.clear.frame(height: dateHeaderHeight + calendarHeight(scroll: 0))
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
                    .padding(.horizontal, 15)
                    .padding(.top, 18)
                    .padding(.bottom, 16)
                }
                .coordinateSpace(name: "dayStack")
                .onPreferenceChange(DayTopKey.self) { dayTops = $0 }
                .background {
                    GeometryReader { geo in
                        Color.clear.preference(key: ScrollTopKey.self, value: geo.frame(in: .named("scrollArea")).minY)
                    }
                }
            }
            .coordinateSpace(name: "scrollArea")
            .modifier(ScrollTracker(y: $scrollY))
            .onPreferenceChange(ScrollTopKey.self) { v in
                if #unavailable(iOS 18) {
                    if restTop == nil { restTop = v }
                    scrollY = (restTop ?? v) - v
                }
            }
            .scrollIndicators(.hidden)
            .foregroundStyle(textColor)
            .background { pageBackground.ignoresSafeArea() }
            .overlay(alignment: .top) {
                VStack(spacing: 0) {
                    header
                        .background {
                            GeometryReader { geo in
                                Color.clear.onAppear { dateHeaderHeight = geo.size.height }
                                    .onChange(of: geo.size.height) { _, h in dateHeaderHeight = h }
                            }
                        }
                    calendarBlock(groups: all) { day in
                        // Jump to that day, or the next day that has events.
                        guard day >= cal.startOfDay(for: now),
                              let target = all.first(where: { $0.day >= day }) else { return }
                        withAnimation(.easeInOut(duration: 0.35)) {
                            proxy.scrollTo(target.day, anchor: UnitPoint(x: 0, y: 0.2))
                        }
                    }
                }
                .background(pageBackground.ignoresSafeArea(edges: .top))
            }
            .refreshable { load() }
        }
    }

    // MARK: Calendar (month that folds into a week strip)

    private let rowH: CGFloat = 40
    private let letterH: CGFloat = 20
    private let circle: CGFloat = 24
    private let topPad: CGFloat = 10
    private let bottomPad: CGFloat = 20

    private var cal: Calendar { Calendar.current }
    private var todayStart: Date { cal.startOfDay(for: now) }
    private var monthStart: Date { cal.dateInterval(of: .month, for: todayStart)?.start ?? todayStart }
    private var monthEnd: Date {
        let end = cal.dateInterval(of: .month, for: todayStart)?.end ?? todayStart
        return cal.date(byAdding: .day, value: -1, to: end) ?? end
    }
    /// First day of the week the month starts in.
    private var gridStart: Date { cal.dateInterval(of: .weekOfYear, for: monthStart)?.start ?? monthStart }
    /// The list (and strip) reach to the end of the month, or two weeks out if that is further.
    private var lastListDay: Date {
        let twoWeeks = cal.date(byAdding: .day, value: 14, to: todayStart) ?? todayStart
        return max(monthEnd, twoWeeks)
    }
    private func dayIndex(_ d: Date) -> Int { cal.dateComponents([.day], from: gridStart, to: d).day ?? 0 }
    private var totalDays: Int { ((dayIndex(lastListDay) + 1 + 6) / 7) * 7 }
    private var monthRows: Int { (dayIndex(monthEnd) + 1 + 6) / 7 }
    private var todayRow: Int { dayIndex(todayStart) / 7 }

    /// How far the list has scrolled while the month is still folding (0 ... until one week is left).
    private func foldScroll(_ s: CGFloat) -> CGFloat {
        max(0, min(s, rowH * CGFloat(max(monthRows - 1, 0))))
    }
    private func gridHeight(scroll s: CGFloat) -> CGFloat {
        max(rowH, CGFloat(monthRows) * rowH - foldScroll(s))
    }
    private func calendarHeight(scroll s: CGFloat) -> CGFloat {
        topPad + letterH + gridHeight(scroll: s) + bottomPad + 1
    }

    /// Where the reader is in the list: `p` is a fractional day position (so the strip glides),
    /// `cur` is the day whose events are first in view (that day gets the orange circle).
    private func dayPosition(_ groups: [(day: Date, events: [AppEvent])]) -> (p: CGFloat, cur: Int) {
        let todayIdx = dayIndex(todayStart)
        let s = max(scrollY, 0)
        let headerBottom = dateHeaderHeight + calendarHeight(scroll: s)
        let pts = groups.compactMap { g -> (y: CGFloat, d: CGFloat)? in
            guard let y = dayTops[g.day] else { return nil }
            return (y, CGFloat(dayIndex(g.day)))
        }.sorted { $0.y < $1.y }
        let v = s + headerBottom + 18
        let cur = pts.last(where: { $0.y <= v + 2 }).map { Int($0.d) } ?? todayIdx
        guard let first = pts.first, v > first.y else { return (CGFloat(todayIdx), max(cur, todayIdx)) }
        for i in 1..<max(pts.count, 1) where i < pts.count {
            if v < pts[i].y {
                let a = pts[i - 1], b = pts[i]
                return (a.d + (b.d - a.d) * ((v - a.y) / max(b.y - a.y, 1)), cur)
            }
        }
        return (pts.last!.d, cur)
    }

    private func calendarBlock(groups: [(day: Date, events: [AppEvent])],
                               jump: @escaping (Date) -> Void) -> some View {
        let total = totalDays
        let pos = dayPosition(groups)
        let p = max(0, min(pos.p, CGFloat(total - 1)))
        let current = max(0, min(pos.cur, total - 1))
        let todayIdx = dayIndex(todayStart)
        let rowStart = CGFloat(todayRow * 7)
        let sc = foldScroll(scrollY)
        // The month folds first (days stay in their columns). After that the orange day moves right
        // across the week, and once it reaches the last column the days slide to keep it in view.
        let ws = max(0, min(max(rowStart, min(p - 6, CGFloat(current))), CGFloat(total - 7)))
        let upcoming = events.filter { $0.end > now }
        let counts = Dictionary(grouping: upcoming) { cal.startOfDay(for: $0.start) }.mapValues { $0.count }
        let days: [Date] = (0..<total).map { cal.date(byAdding: .day, value: $0, to: gridStart) ?? gridStart }

        func cell(_ i: Int, width: CGFloat) -> some View {
            let isCurrent = i == current
            let n = min(counts[days[i]] ?? 0, 3)
            return VStack(spacing: 5) {
                ZStack {
                    if isCurrent { Circle().fill(highlight) }
                    Text(days[i].formatted(.dateTime.day()))
                        .font(.system(size: 14.5, weight: isCurrent || i == todayIdx ? .bold : .regular))
                        .foregroundStyle(isCurrent ? highlightedDateText : (i == todayIdx ? highlight : textColor.opacity(0.5)))
                }
                .frame(width: circle, height: circle)
                HStack(spacing: 3) {
                    ForEach(0..<3, id: \.self) { k in
                        Circle().fill(k < n ? textColor.opacity(0.7) : .clear).frame(width: 4, height: 4)
                    }
                }
            }
            .frame(width: width, height: rowH)
            .opacity(i < current ? 0.6 : 1)
            .contentShape(Rectangle())
            .onTapGesture { jump(days[i]) }
        }

        return GeometryReader { geo in
            let w = geo.size.width
            let cw = (w - 30) / 7
            VStack(spacing: 0) {
                Color.clear.frame(height: topPad)
                // Weekday letters slide with the week row.
                HStack(spacing: 0) {
                    ForEach(0..<total, id: \.self) { i in
                        Text(days[i].formatted(.dateTime.weekday(.narrow)))
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundStyle(textColor.opacity(0.5))
                            .frame(width: cw, height: letterH)
                    }
                }
                .offset(x: 15 - ws * cw)
                .frame(width: w, height: letterH, alignment: .leading)
                .clipped()

                // The rows move up with the list; this week's row stops at the top and the rest slide away.
                ZStack(alignment: .topLeading) {
                    ForEach(0..<monthRows, id: \.self) { r in
                        let y = CGFloat(r) * rowH - sc
                        if r == todayRow {
                            HStack(spacing: 0) {
                                ForEach(0..<total, id: \.self) { i in cell(i, width: cw) }
                            }
                            .offset(x: 15 - ws * cw)
                            .frame(width: w, height: rowH, alignment: .leading)
                            .clipped()
                            .background(pageBackground)
                            .offset(y: max(y, 0))
                            .zIndex(1)
                        } else {
                            HStack(spacing: 0) {
                                ForEach(0..<7, id: \.self) { k in
                                    let i = r * 7 + k
                                    if i < total { cell(i, width: cw) } else { Color.clear.frame(width: cw, height: rowH) }
                                }
                            }
                            .padding(.horizontal, 15)
                            .frame(width: w, height: rowH, alignment: .leading)
                            .offset(y: y)
                        }
                    }
                }
                .frame(width: w, height: gridHeight(scroll: scrollY), alignment: .topLeading)
                .clipped()
                Color.clear.frame(height: bottomPad)
            }
        }
        .frame(height: calendarHeight(scroll: scrollY) - 1)
        .padding(.bottom, 1)
        .background(pageBackground)
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
            if let snap = SharedSettings.weather(at: now) {
                WeatherIconView(name: snap.iconName, color: textColor, size: 43)
            }
        }
        .foregroundStyle(textColor)
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
    @Environment(\.colorScheme) private var scheme
    @State private var themeTick = 0

    var body: some View {
        TabView {
            CalendarTabView()
                .tabItem { Label("Calendar", systemImage: "calendar") }
            ContentView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
        }
        // The selected tab uses your main color (not system blue), like the sister app.
        .tint({ _ = themeTick; return AppTheme(scheme: scheme).ink }())
        .onReceive(NotificationCenter.default.publisher(for: .colorsChanged)) { _ in themeTick += 1 }
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

/// Reports how far the list has scrolled (iOS 18+; older versions use the preference above).
private struct ScrollTracker: ViewModifier {
    @Binding var y: CGFloat
    func body(content: Content) -> some View {
        if #available(iOS 18, *) {
            content.onScrollGeometryChange(for: CGFloat.self) { $0.contentOffset.y + $0.contentInsets.top } action: { _, v in y = v }
        } else {
            content
        }
    }
}
