import SwiftUI
import WidgetKit
import EventKit
import AppIntents

// MARK: - Model

struct CalEvent: Identifiable {
    let id: String
    let title: String
    let start: Date
    let end: Date
    let isAllDay: Bool
    let location: String?
}

/// One visual row in the list: either a bold date header or an event line.
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
    let date: Date            // when this entry becomes active (drives the orange highlight)
    let events: [CalEvent]
    let offset: Int           // paging offset into the flattened row list
}

// MARK: - Provider

struct Provider: TimelineProvider {
    private let store = EKEventStore()
    private let daysAhead = 4

    func placeholder(in context: Context) -> CalendarEntry {
        CalendarEntry(date: .now, events: Self.sample, offset: 0)
    }

    func getSnapshot(in context: Context, completion: @escaping (CalendarEntry) -> Void) {
        completion(CalendarEntry(date: .now, events: context.isPreview ? Self.sample : fetchEvents(), offset: 0))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<CalendarEntry>) -> Void) {
        let events = fetchEvents()
        let offset = Pager.defaults.integer(forKey: Pager.key)
        let now = Date()

        // One entry now, plus one at every event start/end so the orange
        // "happening now" colour flips exactly on time.
        var times: Set<Date> = [now]
        for e in events where !e.isAllDay {
            if e.start > now { times.insert(e.start) }
            if e.end > now { times.insert(e.end) }
        }
        let entries = times.sorted().prefix(40).map {
            CalendarEntry(date: $0, events: events, offset: offset)
        }
        // Refresh at least every 30 min to pick up calendar changes.
        completion(Timeline(entries: entries, policy: .after(now.addingTimeInterval(30 * 60))))
    }

    private func fetchEvents() -> [CalEvent] {
        let status = EKEventStore.authorizationStatus(for: .event)
        guard status == .fullAccess || status == .authorized else { return [] }

        let cal = Calendar.current
        let startOfToday = cal.startOfDay(for: .now)
        guard let end = cal.date(byAdding: .day, value: daysAhead, to: startOfToday) else { return [] }

        let predicate = store.predicateForEvents(withStart: .now.addingTimeInterval(-60 * 60 * 12),
                                                 end: end, calendars: nil)
        return store.events(matching: predicate)
            .filter { $0.endDate > startOfToday }
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

    private var visibleCount: Int {
        switch family {
        case .systemSmall: return 6
        case .systemMedium: return 7
        case .systemLarge: return 18
        default: return 18 // extra large / iPad
        }
    }

    /// Flatten events into header + event rows, grouped by day.
    private var rows: [Row] {
        let cal = Calendar.current
        var result: [Row] = []
        var lastDay: Date?
        for e in entry.events {
            let day = cal.startOfDay(for: max(e.start, cal.startOfDay(for: entry.date)))
            if day != lastDay {
                result.append(.header(day))
                lastDay = day
            }
            result.append(.event(e))
        }
        return result
    }

    /// Space each row takes, in single-line units:
    /// today's big header = 3, other date headers = 1, events (two lines) = 2.
    private func weight(_ row: Row) -> Int {
        switch row {
        case .header(let day): return isToday(day) ? 3 : 1
        case .event: return 2
        }
    }

    private func isToday(_ day: Date) -> Bool {
        Calendar.current.isDate(day, inSameDayAs: entry.date)
    }

    /// Which rows fit in the widget, given the paging offset.
    private var windowRange: Range<Int> {
        let all = rows
        guard !all.isEmpty else { return 0..<0 }
        let start = min(entry.offset, all.count - 1)
        var used = 0
        var end = start
        while end < all.count {
            let w = weight(all[end])
            if used + w > visibleCount && end > start { break }
            used += w
            end += 1
        }
        return start..<end
    }

    private var window: [Row] { Array(rows[windowRange]) }

    private var canPageUp: Bool { windowRange.lowerBound > 0 }
    private var canPageDown: Bool { windowRange.upperBound < rows.count }

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            VStack(alignment: .leading, spacing: 3) {
                if entry.events.isEmpty {
                    Text("No events in the next 4 days")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(Array(window.enumerated()), id: \.element.id) { index, row in
                        rowView(row, isFirst: index == 0)
                    }
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if canPageUp || canPageDown {
                VStack(spacing: 8) {
                    Button(intent: PageIntent(delta: -Pager.step)) {
                        Image(systemName: "chevron.up")
                    }
                    .disabled(!canPageUp)
                    Spacer(minLength: 0)
                    Button(intent: PageIntent(delta: Pager.step)) {
                        Image(systemName: "chevron.down")
                    }
                    .disabled(!canPageDown)
                }
                .buttonStyle(.plain)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            }
        }
        .containerBackground(.clear, for: .widget) // transparent background
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
                        .fill(Color.primary.opacity(0.35))
                        .frame(height: 1 / displayScale)
                        .padding(.vertical, 2)
                }
                if isToday(day) {
                    // Today: two lines. Weekday bold, then date + month larger and light.
                    VStack(alignment: .leading, spacing: 0) {
                        Text(day.formatted(.dateTime.weekday(.wide)))
                            .font(.system(size: 18, weight: .bold))
                        Text(day.formatted(.dateTime.day().month(.wide)))
                            .font(.system(size: 24, weight: .thin))
                    }
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                } else {
                    Text(day.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))
                        .font(.subheadline.bold())
                }
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
            .foregroundStyle(active ? Color.orange : Color.primary)
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
        .description("Your next 4 days of events. Current event shows in orange.")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

@main
struct CalendarWidgetBundle: WidgetBundle {
    var body: some Widget {
        CalendarListWidget()
    }
}
