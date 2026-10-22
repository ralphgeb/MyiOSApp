import SwiftUI
import WidgetKit
import EventKit
import AppIntents

// MARK: - Layout constants

enum Layout {
    /// Space under today's date before the first event. The old gap was 3 pt of layout
    /// (about 10 pt visible); 8 pt here makes the visible gap about 1.5x bigger.
    static let headerGap: CGFloat = 8
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

    var id: String {
        switch self {
        case .header(let d): return "h-\(d.timeIntervalSince1970)"
        case .event(let e): return "e-\(e.id)-\(e.start.timeIntervalSince1970)"
        }
    }
}

struct CalendarEntry: TimelineEntry {
    let date: Date               // when this entry becomes active (drives the orange highlight)
    let events: [CalEvent]
    let page: Int                // which page of events to show
    let weatherSymbol: String?   // SF Symbol name, nil = no weather yet
    let background: Color
    let textColor: Color
}

// MARK: - Provider

struct Provider: TimelineProvider {
    private let store = EKEventStore()

    func placeholder(in context: Context) -> CalendarEntry {
        makeEntry(date: .now, events: Self.sample, weather: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (CalendarEntry) -> Void) {
        let events = context.isPreview ? Self.sample : fetchEvents()
        completion(makeEntry(date: .now, events: events, weather: SharedSettings.weather))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<CalendarEntry>) -> Void) {
        Task {
            let events = fetchEvents()
            let weather = await WeatherProvider.current()
            let now = Date()

            // One entry now, plus one at every event start/end so the orange
            // "happening now" colour flips exactly on time, plus one at midnight
            // so today's date rolls over.
            var times: Set<Date> = [now]
            for e in events where !e.isAllDay {
                if e.start > now { times.insert(e.start) }
                if e.end > now { times.insert(e.end) }
            }
            if let midnight = Calendar.current.nextDate(after: now, matching: DateComponents(hour: 0, minute: 0),
                                                        matchingPolicy: .nextTime) {
                times.insert(midnight)
            }
            let entries = times.sorted().prefix(40).map {
                makeEntry(date: $0, events: events, weather: weather)
            }
            // Refresh at least every 30 min to pick up calendar and weather changes.
            completion(Timeline(entries: entries, policy: .after(now.addingTimeInterval(30 * 60))))
        }
    }

    private func makeEntry(date: Date, events: [CalEvent], weather: SharedSettings.WeatherSnapshot?) -> CalendarEntry {
        CalendarEntry(date: date,
                      events: events,
                      page: Pager.page,
                      weatherSymbol: weather?.symbolName,
                      background: SharedSettings.backgroundColor?.color ?? .clear,
                      textColor: SharedSettings.textColor?.color ?? .primary)
    }

    private func fetchEvents() -> [CalEvent] {
        let status = EKEventStore.authorizationStatus(for: .event)
        guard status == .fullAccess || status == .authorized else { return [] }

        let cal = Calendar.current
        let startOfToday = cal.startOfDay(for: .now)
        guard let end = cal.date(byAdding: .day, value: SharedSettings.daysAhead, to: startOfToday) else { return [] }

        // Only the calendars the user left switched on in the app.
        let hidden = SharedSettings.hiddenCalendarIDs
        let selected = store.calendars(for: .event).filter { !hidden.contains($0.calendarIdentifier) }
        guard !selected.isEmpty else { return [] }

        let predicate = store.predicateForEvents(withStart: .now.addingTimeInterval(-60 * 60 * 12),
                                                 end: end, calendars: selected)
        return store.events(matching: predicate)
            .filter { $0.endDate > startOfToday }
            .filter { SharedSettings.showAllDay || !$0.isAllDay }
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

    /// Space for the paged list under the pinned header, in single-line units
    /// (event = 2, date header = 1).
    private var capacity: Int {
        switch family {
        case .systemSmall: return 3
        case .systemMedium: return 4
        default: return 15
        }
    }

    private func weight(_ row: Row) -> Int {
        if case .event = row { return 2 }
        return 1
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
        for e in entry.events {
            let d = day(of: e)
            if d != lastDay {
                if !isToday(d) { result.append(.header(d)) }
                lastDay = d
            }
            result.append(.event(e))
        }
        return result
    }

    /// Splits the rows into pages. A page never ends on a lonely date header
    /// (that day moves to the next page), and a page that starts part-way
    /// through a day gets that day's header re-added on top.
    private var pages: [[Row]] {
        let all = rows
        var pages: [[Row]] = []
        var i = 0
        while i < all.count {
            var page: [Row] = []
            var used = 0
            var added = 0
            if case .event(let e) = all[i], !isToday(day(of: e)) {
                page.append(.header(day(of: e)))
                used += 1
            }
            while i < all.count {
                let w = weight(all[i])
                if used + w > capacity && added > 0 { break }
                page.append(all[i])
                used += w
                added += 1
                i += 1
            }
            if case .header? = page.last, added > 1 {
                page.removeLast()
                i -= 1
            }
            pages.append(page)
        }
        return pages
    }

    var body: some View {
        let allPages = pages
        let pageIndex = min(entry.page, max(0, allPages.count - 1))
        let current = allPages.isEmpty ? [] : allPages[pageIndex]
        let canPageUp = pageIndex > 0
        let canPageDown = pageIndex < allPages.count - 1

        HStack(alignment: .top, spacing: 6) {
            VStack(alignment: .leading, spacing: 0) {
                pinnedHeader
                    .padding(.bottom, Layout.headerGap)

                VStack(alignment: .leading, spacing: 3) {
                    if entry.events.isEmpty {
                        Text("No events to show")
                            .font(.footnote)
                            .opacity(0.6)
                    } else {
                        ForEach(Array(current.enumerated()), id: \.element.id) { index, row in
                            rowView(row, isFirst: index == 0)
                        }
                    }
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if canPageUp || canPageDown {
                VStack(spacing: 8) {
                    Button(intent: PageIntent(target: pageIndex - 1)) {
                        Image(systemName: "chevron.up")
                    }
                    .disabled(!canPageUp)
                    .opacity(canPageUp ? 1 : 0.3)
                    Spacer(minLength: 0)
                    Button(intent: PageIntent(target: pageIndex + 1)) {
                        Image(systemName: "chevron.down")
                    }
                    .disabled(!canPageDown)
                    .opacity(canPageDown ? 1 : 0.3)
                }
                .buttonStyle(.plain)
                .font(.caption.weight(.semibold))
                .foregroundStyle(entry.textColor.opacity(0.7))
            }
        }
        .foregroundStyle(entry.textColor)
        .containerBackground(entry.background, for: .widget)
    }

    /// Today: weekday bold, date + month larger and thin, weather icon at the right.
    /// Stays on screen whichever page is showing.
    private var pinnedHeader: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 0) {
                Text(entry.date.formatted(.dateTime.weekday(.wide)))
                    .font(.system(size: 18, weight: .bold))
                Text(entry.date.formatted(.dateTime.day().month(.wide)))
                    .font(.system(size: 24, weight: .thin))
            }
            .lineLimit(1)
            .minimumScaleFactor(0.8)

            Spacer(minLength: 0)

            if let symbol = entry.weatherSymbol {
                Image(systemName: symbol)
                    .font(.system(size: 30, weight: .ultraLight))   // thin line icon
                    .symbolRenderingMode(.monochrome)
                    .padding(.top, 2)
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
            VStack(alignment: .leading, spacing: 3) {
                // Hairline between days: exactly one physical pixel thick.
                if !isFirst {
                    Rectangle()
                        .fill(entry.textColor.opacity(0.35))
                        .frame(height: 1 / displayScale)
                        .padding(.vertical, 2)
                }
                Text(day.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))
                    .font(.subheadline.bold())
            }
        case .event(let e):
            let active = !e.isAllDay && e.start <= entry.date && e.end > entry.date
            // Two columns so the title and location line up:
            //   15:30  Stand-up
            //   16:00  Meeting room 2
            HStack(alignment: .top, spacing: 6) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(e.isAllDay ? "All day" : clock(e.start))
                        .font(.system(size: 14, weight: .bold))
                    Text(e.isAllDay ? " " : clock(e.end))
                        .font(.system(size: 12, weight: .regular))
                }
                .fontWidth(.condensed)   // narrower letterforms (iOS 16.4+)
                .monospacedDigit()

                VStack(alignment: .leading, spacing: 0) {
                    Text(e.title)
                        .font(.system(size: 14, weight: .medium))
                        .lineLimit(1)
                    Text(e.location ?? " ")
                        .font(.system(size: 12, weight: .light))
                        .italic()
                        .lineLimit(1)
                }
            }
            .foregroundStyle(active ? Color.orange : entry.textColor)
        }
    }
}

// MARK: - Widget

struct CalendarListWidget: Widget {
    let kind = "CalendarListWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            CalendarWidgetView(entry: entry)
        }
        .configurationDisplayName("Upcoming Events")
        .description("Your upcoming events. Current event shows in orange.")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

@main
struct CalendarWidgetBundle: WidgetBundle {
    var body: some Widget {
        CalendarListWidget()
    }
}
