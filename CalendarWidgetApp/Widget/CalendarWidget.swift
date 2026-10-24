import SwiftUI
import UIKit
import WidgetKit
import EventKit
import AppIntents

// MARK: - Layout constants

enum Layout {
    /// Space under today's date before the first event (about 1.5x the original gap).
    static let headerGap: CGFloat = 8

    /// Space between "Thursday" and "22 October". Negative pulls the lines closer.
    static let dateLineSpacing: CGFloat = -5

    /// White space between one day's last event and the next day's header, with the hairline
    /// in the middle. Matches the gap under today's date (a little extra makes up for the
    /// smaller text sizes around the hairline).
    static let dayGap: CGFloat = 18
}

// MARK: - Model

struct CalEvent: Identifiable {
    let id: String
    let title: String
    let start: Date
    let end: Date
    let isAllDay: Bool
    let location: String?
}

/// One row in the paged list: a date header or an event (two lines).
/// Today's date is NOT a row: it stays pinned at the top of every page.
enum Row: Identifiable {
    case header(Date)
    case event(CalEvent)
    case endOfDay(Date)        // hairline closing a day whose next day didn't fit on this page
    case peek(CalEvent)        // only the first line of an event, to fill leftover space at the bottom

    var id: String {
        switch self {
        case .header(let d): return "h-\(d.timeIntervalSince1970)"
        case .endOfDay(let d): return "end-\(d.timeIntervalSince1970)"
        case .peek(let e): return "p-\(e.id)-\(e.start.timeIntervalSince1970)"
        case .event(let e): return "e-\(e.id)-\(e.start.timeIntervalSince1970)"
        }
    }
}

struct CalendarEntry: TimelineEntry {
    let date: Date                              // when this entry becomes active (drives the orange highlight)
    let events: [CalEvent]
    let page: Int                               // which page of events to show
    let direction: Int                          // +1 slid down, -1 slid up (for the page animation)
    let weatherIcon: String?                    // custom icon name, nil = no weather yet
    let colors: SharedSettings.ColorSettings    // resolved for light/dark when drawing
    let isPro: Bool                             // unlocked? (previews in the gallery always show content)
}

// MARK: - Provider

struct Provider: TimelineProvider {
    private let store = EKEventStore()
    var includeWeather = true      // the Lock Screen widget doesn't need weather

    func placeholder(in context: Context) -> CalendarEntry {
        makeEntry(date: .now, events: Self.sample, weather: nil, preview: true, family: context.family)
    }

    func getSnapshot(in context: Context, completion: @escaping (CalendarEntry) -> Void) {
        let events = context.isPreview ? Self.sample : fetchEvents()
        completion(makeEntry(date: .now, events: events,
                             weather: includeWeather ? SharedSettings.weather(at: .now) : nil,
                             preview: context.isPreview, family: context.family))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<CalendarEntry>) -> Void) {
        Task {
            let events = fetchEvents()
            // Weather must never hold up the widget: wait at most 5 seconds, then use the saved value.
            if includeWeather {
                _ = await withTimeout(5) { () async -> Bool? in
                    await WeatherProvider.refreshIfNeeded()
                    return true
                }
            }   // WeatherKit is only called when the saved 24 hours are running out
            let now = Date()

            // Battery: plan only the next few hours. One entry now, one at each event start/end
            // (so the orange "happening now" color flips on time) and one at midnight.
            // The system then asks for a fresh timeline after 30 minutes, which also picks up new calendar events.
            let horizon = now.addingTimeInterval(4 * 3600)
            var times: Set<Date> = [now]
            for e in events where !e.isAllDay {
                if e.start > now && e.start < horizon { times.insert(e.start) }
                if e.end > now && e.end < horizon { times.insert(e.end) }
            }
            if let midnight = Calendar.current.nextDate(after: now, matching: DateComponents(hour: 0, minute: 0),
                                                        matchingPolicy: .nextTime), midnight < horizon {
                times.insert(midnight)
            }
            let entries = times.sorted().prefix(16).map {
                makeEntry(date: $0, events: events,
                          weather: includeWeather ? SharedSettings.weather(at: $0) : nil,
                          family: context.family)
            }
            completion(Timeline(entries: entries, policy: .after(now.addingTimeInterval(30 * 60))))
        }
    }

    private func makeEntry(date: Date, events: [CalEvent], weather: SharedSettings.WeatherSnapshot?,
                           preview: Bool = false,
                           family: WidgetFamily) -> CalendarEntry {
        CalendarEntry(date: date,
                      events: events,
                      page: Pager.page(for: family),
                      direction: Pager.direction,
                      weatherIcon: weather?.iconName,
                      colors: SharedSettings.isPro
                        ? SharedSettings.colorSettings
                        : SharedSettings.ColorSettings(ignoreAppearance: false, both: .init(), light: .init(), dark: .init()),
                      isPro: preview || SharedSettings.isPro)
    }

    private func fetchEvents() -> [CalEvent] {
        let status = EKEventStore.authorizationStatus(for: .event)
        guard status == .fullAccess || status == .authorized else { return [] }

        let cal = Calendar.current
        let startOfToday = cal.startOfDay(for: .now)
        guard let end = cal.date(byAdding: .day, value: SharedSettings.isPro ? SharedSettings.daysAhead : SharedSettings.freeDays, to: startOfToday) else { return [] }

        // Only the calendars the user left switched on in the app.
        let hidden = SharedSettings.isPro ? SharedSettings.hiddenCalendarIDs : []
        let selected = store.calendars(for: .event).filter { !hidden.contains($0.calendarIdentifier) }
        guard !selected.isEmpty else { return [] }

        let predicate = store.predicateForEvents(withStart: startOfToday, end: end, calendars: selected)
        return store.events(matching: predicate)
            .filter { !SharedSettings.isPro || SharedSettings.showAllDay || !$0.isAllDay }
            .sorted { $0.startDate < $1.startDate }
            .map { CalEvent(id: $0.eventIdentifier ?? UUID().uuidString,
                            title: $0.title ?? "Untitled",
                            start: $0.startDate, end: $0.endDate, isAllDay: $0.isAllDay,
                            location: ($0.location?.isEmpty == false) ? $0.location : nil) }
    }

    static let sample: [CalEvent] = {
        let n = Date()
        return [
            CalEvent(id: "1", title: "Stand-up", start: n.addingTimeInterval(-600), end: n.addingTimeInterval(1200), isAllDay: false, location: "Meeting room 2"),
            CalEvent(id: "2", title: "Lunch with Sam", start: n.addingTimeInterval(7200), end: n.addingTimeInterval(10800), isAllDay: false, location: "Rosa's Cafe"),
            CalEvent(id: "3", title: "Design review", start: n.addingTimeInterval(90000), end: n.addingTimeInterval(93600), isAllDay: false, location: nil),
        ]
    }()
}

// MARK: - View

struct CalendarWidgetView: View {
    let entry: CalendarEntry
    @Environment(\.widgetFamily) private var family
    @Environment(\.displayScale) private var displayScale
    @Environment(\.colorScheme) private var scheme

    // MARK: Colors (custom colors, or the system defaults)

    private var colorSet: SharedSettings.ColorSet { entry.colors.resolved(for: scheme) }
    private var textColor: Color { colorSet.text?.color ?? .primary }
    private var highlightColor: Color { colorSet.highlight?.color ?? .orange }
    private var backgroundColor: Color { colorSet.background?.color ?? .clear }

    // MARK: Paging

    /// Number of side-by-side columns: the wide extra large widget on iPad uses two.
    /// On iPhone (iOS 27) the extra large widget is tall, so it stays one column.
    private var columns: Int {
        family == .systemExtraLarge && UIDevice.current.userInterfaceIdiom == .pad ? 2 : 1
    }

    /// Approximate on-screen heights (points) used to decide how many rows fit.
    private enum Cost {
        static let event: CGFloat = 35          // two lines + spacing
        static let allDay: CGFloat = 22         // one line
        static let peek: CGFloat = 18           // first line of an event only
        static let endRule: CGFloat = Layout.dayGap / 2 + 2
        static let header: CGFloat = 23         // "Fri 23 Oct"
        static let separator: CGFloat = Layout.dayGap + 2   // hairline and its padding
        static let pinnedHeader: CGFloat = 46 + Layout.headerGap
        static let safety: CGFloat = 6
    }

    private var isMedium: Bool { family == .systemMedium }

    private func cost(_ row: Row, firstInChunk: Bool) -> CGFloat {
        switch row {
        case .event(let e):
            if e.isAllDay && e.location == nil { return Cost.allDay }
            return isMedium ? 33 : Cost.event      // medium packs two events under the header
        case .endOfDay: return Cost.endRule
        case .peek: return Cost.peek
        case .header: return Cost.header + (firstInChunk ? 0 : Cost.separator)
        }
    }

    private func isToday(_ day: Date) -> Bool {
        Calendar.current.isDate(day, inSameDayAs: entry.date)
    }

    private func day(of e: CalEvent) -> Date {
        let cal = Calendar.current
        return cal.startOfDay(for: max(e.start, cal.startOfDay(for: entry.date)))
    }

    /// Events grouped by day. Today has no header row (it's pinned above).
    private var rows: [Row] {
        var result: [Row] = []
        var lastDay: Date?
        // Events that have already finished are hidden, so the first row is always what's on now or next.
        for e in entry.events where e.end > entry.date {
            let d = day(of: e)
            if d != lastDay {
                if !isToday(d) { result.append(.header(d)) }
                lastDay = d
            }
            result.append(.event(e))
        }
        return result
    }

    /// Splits the rows into column-sized chunks. A chunk never ends on a lonely date header
    /// (that day moves to the next chunk), and a chunk that starts part-way through a day
    /// gets that day's header re-added on top. One chunk per page, or two on the XL widget.
    private func chunkEndsWithPreview(_ chunk: [Row]) -> Bool {
        if case .peek? = chunk.last { return true }
        return false
    }

    private func chunks(fitting height: CGFloat) -> [[Row]] {
        let capacity = max(Cost.event, height - Cost.pinnedHeader - (isMedium ? 0 : Cost.safety))
        let all = rows
        var result: [[Row]] = []
        var i = 0
        while i < all.count {
            var chunk: [Row] = []
            var used: CGFloat = 0
            var added = 0
            if case .event(let e) = all[i], !isToday(day(of: e)) {
                chunk.append(.header(day(of: e)))
                used += Cost.header
            }
            while i < all.count {
                let w = cost(all[i], firstInChunk: chunk.isEmpty)
                if used + w > capacity && added > 0 { break }
                chunk.append(all[i])
                used += w
                added += 1
                i += 1
            }
            // Leftover space at the bottom: fill it with the first line of the next event
            // (and the next day's heading if that event starts a new day), so there is no big gap.
            // The next page still starts with that event in full.
            var remaining = capacity - used
            if case .header? = chunk.last, added > 1 {
                // A day heading fit but its first event didn't.
                if i < all.count, case .event(let e) = all[i], remaining >= Cost.peek {
                    chunk.append(.peek(e))
                } else {
                    chunk.removeLast()
                    i -= 1
                    used -= Cost.header
                    remaining = capacity - used
                }
            } else if i < all.count, !chunk.isEmpty {
                switch all[i] {
                case .event(let e):
                    if remaining >= Cost.peek { chunk.append(.peek(e)) }
                case .header(let nextDay):
                    if i + 1 < all.count, case .event(let e) = all[i + 1],
                       remaining >= Cost.header + Cost.separator + Cost.peek {
                        chunk.append(.header(nextDay))
                        chunk.append(.peek(e))
                    }
                default: break
                }
            }
            // Nothing could be added and the day is over: close it with a hairline.
            if i < all.count, case .header(let nextDay) = all[i], !chunk.isEmpty,
               !chunkEndsWithPreview(chunk), remaining >= Cost.endRule {
                chunk.append(.endOfDay(nextDay))
            }
            result.append(chunk)
        }
        return result
    }

    var body: some View {
        if !entry.isPro && family != .systemSmall && family != .systemLarge && family != .accessoryRectangular {
            // Only the small (2x2) and large (4x4) widgets are free; every other size is part of the unlock.
            VStack(spacing: 6) {
                Image(systemName: "lock.fill").font(.title2)
                Text("Unlock in the app").font(.system(size: 15, weight: .semibold))
                Text("Settings → Unlock All Widgets")
                    .font(.system(size: 12))
                    .opacity(0.7)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .foregroundStyle(textColor)
            .containerBackground(backgroundColor, for: .widget)
        } else if family == .accessoryRectangular {
            lockScreen
                .containerBackground(.clear, for: .widget)
        } else if family == .systemSmall {
            smallView
                .containerBackground(backgroundColor, for: .widget)
        } else {
            GeometryReader { geo in
                content(height: geo.size.height)
            }
            .foregroundStyle(textColor)
            .containerBackground(backgroundColor, for: .widget)
        }
    }

    // MARK: Small (2x2): day, date and the next event

    private var smallView: some View {
        let cal = Calendar.current
        let now = entry.date
        let next = entry.events.first { $0.end > now }
        return VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: Layout.dateLineSpacing) {
                Text(now.formatted(.dateTime.weekday(.wide)))
                    .font(.system(size: 16, weight: .bold))
                Text(now.formatted(.dateTime.day().month(.wide)))
                    .font(.system(size: 22, weight: .thin))
            }
            .lineLimit(1)
            .minimumScaleFactor(0.7)

            Spacer(minLength: 8)

            if let e = next {
                let active = !e.isAllDay && e.start <= now && e.end > now
                VStack(alignment: .leading, spacing: 1) {
                    if !cal.isDate(e.start, inSameDayAs: now) && e.start > now {
                        Text(e.start.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))
                            .font(.system(size: 12, weight: .semibold))
                            .opacity(0.7)
                    }
                    Text(e.isAllDay ? "All day" : "\(clock(e.start))–\(clock(e.end))")
                        .font(.system(size: 14, weight: .bold))
                        .monospacedDigit()
                    Text(e.title)
                        .font(.system(size: 14, weight: .medium))
                        .lineLimit(2)
                    if let loc = e.location {
                        Text(loc)
                            .font(.system(size: 12))
                            .italic()
                            .lineLimit(1)
                            .opacity(0.85)
                    }
                }
                .foregroundStyle(active ? highlightColor : textColor)
            } else {
                Text("No upcoming events")
                    .font(.footnote)
                    .opacity(0.6)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .foregroundStyle(textColor)
    }

    // MARK: Lock Screen (rectangular): always three events, running on into the next days

    private var lockScreen: some View {
        let cal = Calendar.current
        let now = entry.date
        let upcoming = entry.events.filter { $0.end > now }
        // Events still to come today (including one that is on right now), then whatever follows.
        let isToday: (CalEvent) -> Bool = { cal.isDate($0.start, inSameDayAs: now) || $0.start < now }
        let lines = Array((upcoming.filter(isToday) + upcoming.filter { !isToday($0) }).prefix(3))

        return VStack(alignment: .leading, spacing: 1) {
            if !entry.isPro {
                Label("Unlock in the app", systemImage: "lock.fill")
                    .font(.system(size: 13, weight: .semibold))
                Text("Lock Screen widget is part of the unlock")
                    .font(.system(size: 11))
                    .opacity(0.7)
                    .lineLimit(2)
            } else if !lines.isEmpty {
                ForEach(lines, id: \.id) { e in
                    lockLine(e, now: now, today: isToday(e))
                }
            } else {
                Text("No upcoming events")
                    .font(.system(size: 13, weight: .semibold))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// "Tomorrow" or the date for events that are not today.
    private func dayLabel(_ d: Date, now: Date) -> String {
        let cal = Calendar.current
        if let tomorrow = cal.date(byAdding: .day, value: 1, to: now), cal.isDate(d, inSameDayAs: tomorrow) {
            return "Tomorrow"
        }
        return d.formatted(.dateTime.weekday(.abbreviated).day())
    }

    private func lockLine(_ e: CalEvent, now: Date, today: Bool) -> some View {
        let active = !e.isAllDay && e.start <= now && e.end > now
        let label = !today ? dayLabel(e.start, now: now) : (e.isAllDay ? "All day" : clock(e.start))
        return HStack(spacing: 5) {
            Text(label)
                .font(.system(size: 15, weight: .bold))
                .monospacedDigit()
                .lineLimit(1)
                .fixedSize()
            Text(e.title)
                .font(.system(size: 15, weight: active ? .semibold : .regular))
                .lineLimit(1)
        }
    }

    @ViewBuilder
    private func content(height: CGFloat) -> some View {
        let allChunks = chunks(fitting: height)
        let pageCount = max(1, (allChunks.count + columns - 1) / columns)
        let pageIndex = min(entry.page, pageCount - 1)
        let lower = min(pageIndex * columns, allChunks.count)
        let upper = min(lower + columns, allChunks.count)
        let shown = Array(allChunks[lower..<upper])
        let canPageUp = pageIndex > 0
        let canPageDown = pageIndex < pageCount - 1

        HStack(alignment: .top, spacing: 6) {
            VStack(alignment: .leading, spacing: 0) {
                pinnedHeader
                    .padding(.bottom, Layout.headerGap)

                if rows.isEmpty {
                    Text("No events to show")
                        .font(.footnote)
                        .opacity(0.6)
                } else {
                    // Whole list slides as one block: new rows rise in from the bottom when going
                    // down (or drop in from the top when going up) while the pinned header stays put.
                    HStack(alignment: .top, spacing: 18) {
                        ForEach(Array(shown.enumerated()), id: \.offset) { _, chunk in
                            VStack(alignment: .leading, spacing: 3) {
                                ForEach(Array(chunk.enumerated()), id: \.element.id) { index, row in
                                    rowView(row, isFirst: index == 0)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                        }
                    }
                    .id(pageIndex)
                    .transition(.push(from: entry.direction >= 0 ? .bottom : .top))
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if canPageUp || canPageDown {
                // Small arrows with big tap zones (44 pt wide): top half pages up, bottom half pages down.
                VStack(spacing: 0) {
                    Button(intent: PageIntent(target: pageIndex - 1, family: "\(family)")) {
                        Image(systemName: "chevron.up")
                            .opacity(canPageUp ? 1 : 0.3)
                            .frame(width: 44, height: 70, alignment: .top)
                            .contentShape(Rectangle())
                    }
                    .disabled(!canPageUp)
                    Spacer(minLength: 0)
                    Button(intent: PageIntent(target: pageIndex + 1, family: "\(family)")) {
                        Image(systemName: "chevron.down")
                            .opacity(canPageDown ? 1 : 0.3)
                            .frame(width: 44, height: 70, alignment: .bottom)
                            .contentShape(Rectangle())
                    }
                    .disabled(!canPageDown)
                }
                .buttonStyle(.plain)
                .font(.caption.weight(.semibold))
                .foregroundStyle(textColor.opacity(0.7))
                .frame(width: 44)
                .padding(.horizontal, -16)
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    /// Today: weekday bold, date + month larger and thin, weather icon at the right
    /// (centered on the two lines). Stays on screen whichever page is showing.
    private var pinnedHeader: some View {
        HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: Layout.dateLineSpacing) {
                Text(entry.date.formatted(.dateTime.weekday(.wide)))
                    .font(.system(size: 18, weight: .bold))
                Text(entry.date.formatted(.dateTime.day().month(.wide)))
                    .font(.system(size: 24, weight: .thin))
            }
            .lineLimit(1)
            .minimumScaleFactor(0.8)

            Spacer(minLength: 0)

            if let icon = entry.weatherIcon {
                WeatherIconView(name: icon, color: textColor, size: 40)
            }
        }
    }

    /// "15:30"
    private func clock(_ d: Date) -> String {
        d.formatted(Date.FormatStyle().hour().minute())
    }

    @ViewBuilder
    private func rowView(_ row: Row, isFirst: Bool) -> some View {
        switch row {
        case .header(let day):
            VStack(alignment: .leading, spacing: 0) {
                // Hairline between days: one physical pixel thick, with equal space above and below
                // that adds up to Layout.dayGap (the list already adds 3 pt above).
                if !isFirst {
                    Rectangle()
                        .fill(textColor.opacity(0.35))
                        .frame(height: 1 / displayScale)
                        .padding(.top, Layout.dayGap / 2)
                        .padding(.bottom, Layout.dayGap / 2)
                }
                Text(day.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))
                    .font(.subheadline.bold())
            }
        case .endOfDay:
            Rectangle()
                .fill(textColor.opacity(0.35))
                .frame(height: 1 / displayScale)
                .padding(.top, Layout.dayGap / 2)
        case .event(let e), .peek(let e):
            let isPeek: Bool = { if case .peek = row { return true }; return false }()
            let active = !e.isAllDay && e.start <= entry.date && e.end > entry.date
            // Two columns so the title and location line up:
            //   15:30  Stand-up
            //   16:00  Meeting room 2
            HStack(alignment: .top, spacing: 6) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(e.isAllDay ? "All day" : clock(e.start))
                        .font(.system(size: 14, weight: .bold))
                    if !isPeek && !(e.isAllDay && e.location == nil) {
                        Text(e.isAllDay ? " " : clock(e.end))
                            .font(.system(size: 12, weight: .regular))
                    }
                }
                .fontWidth(.condensed)   // narrower letterforms (iOS 16.4+)
                .monospacedDigit()

                VStack(alignment: .leading, spacing: 0) {
                    Text(e.title)
                        .font(.system(size: 14, weight: .medium))
                        .lineLimit(1)
                    if !isPeek && (!e.isAllDay || e.location != nil) {
                        Text(e.location ?? " ")
                            .font(.system(size: 12, weight: .light))
                            .italic()
                            .lineLimit(1)
                    }
                }
            }
            .foregroundStyle(active ? highlightColor : textColor)
        }
    }
}

// MARK: - Widget

struct CalendarListWidget: Widget {
    static let kind = SharedSettings.widgetKind
    let kind = SharedSettings.widgetKind

    static var families: [WidgetFamily] {
        var f: [WidgetFamily] = [.systemSmall, .systemMedium, .systemLarge, .systemExtraLarge, .accessoryRectangular]
        #if compiler(>=6.4)
        if #available(iOS 27, *) { f.append(.systemExtraLargePortrait) }
        #endif
        return f
    }

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            CalendarWidgetView(entry: entry)
        }
        .configurationDisplayName("Upcoming Events")
        .description("Your upcoming events. Current event shows in orange.")
        // Extra large: iPad. On iPhone, iOS 27 adds a full-page 4x6 size (needs the iOS 27 SDK).
        .supportedFamilies(Self.families)
    }
}

// MARK: - Lock Screen widget with one event: time range + title (2 lines), then location

struct NextEventLockView: View {
    let entry: CalendarEntry

    private func clock(_ d: Date) -> String {
        d.formatted(Date.FormatStyle().hour().minute())
    }

    var body: some View {
        let now = entry.date
        let next = entry.events.first { $0.end > now }
        VStack(alignment: .leading, spacing: 0) {
            if !entry.isPro {
                Label("Unlock in the app", systemImage: "lock.fill")
                    .font(.system(size: 13, weight: .semibold))
                Text("Lock Screen widget is part of the unlock")
                    .font(.system(size: 11))
                    .opacity(0.7)
                    .lineLimit(2)
            } else if let e = next {
                // Three lines, all the same size: time range, title, location.
                let size: CGFloat = 16.5
                Group {
                    if e.isAllDay {
                        Text("All day").bold()
                    } else {
                        Text(clock(e.start)).bold().monospacedDigit()
                            + Text("–").fontWeight(.light)
                            + Text(clock(e.end)).bold().monospacedDigit()
                    }
                }
                .font(.system(size: size))
                .lineLimit(1)
                Text(e.title)
                    .font(.system(size: size, weight: .medium))
                    .lineLimit(e.location == nil ? 2 : 1)
                if let loc = e.location {
                    Text(loc)
                        .font(.system(size: size, weight: .thin))
                        .italic()
                        .lineLimit(1)
                }
            } else {
                Text("No upcoming events")
                    .font(.system(size: 13, weight: .semibold))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .containerBackground(.clear, for: .widget)
    }
}

struct NextEventLockWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: SharedSettings.nextEventKind, provider: Provider(includeWeather: false)) { entry in
            NextEventLockView(entry: entry)
        }
        .configurationDisplayName("Next Event")
        .description("Your next event on the Lock Screen: time, title and location.")
        .supportedFamilies([.accessoryRectangular])
    }
}

@main
struct CalendarWidgetBundle: WidgetBundle {
    var body: some Widget {
        CalendarListWidget()
        NextEventLockWidget()
    }
}
