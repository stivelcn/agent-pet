import Foundation
import AgentPetCore

/// Read-only reporting over the actual local ledger, never inferred from pet XP
/// or lifetime counters. Missing records and missing token counts stay distinct.
@MainActor
struct UsageHistoryReport {
    enum Grain: String, CaseIterable {
        case daily, monthly
        var title: String { self == .daily ? "By day" : "By month" }
    }

    struct Totals: Equatable {
        var tokens = 0
        var completions = 0
        var recordCount = 0
        var tokenRecordCount = 0
        var hasRecords: Bool { recordCount > 0 }
        var hasTokenData: Bool { tokenRecordCount > 0 }

        init(rows: [ProjectUsageStore.Row] = []) {
            tokens = rows.reduce(0) { $0 + $1.tokens }
            completions = rows.reduce(0) { $0 + $1.sessions }
            recordCount = rows.count
            tokenRecordCount = rows.filter { $0.tokens > 0 }.count
        }
    }

    struct Bucket: Identifiable {
        let id: String
        let label: String
        let totals: Totals
    }

    /// Monday-first columns. Padding is not a date and must never be clickable.
    struct Heatmap {
        struct Week: Identifiable {
            let id: String
            let days: [Bucket?]
        }
        struct MonthMarker: Identifiable {
            let id: String
            let column: Int
            let date: Date
        }
        let startKey: String
        let endKey: String
        let timeZone: TimeZone
        let weeks: [Week]
        let months: [MonthMarker]
        let totals: Totals
        var days: [Bucket] { weeks.flatMap { $0.days.compactMap { $0 } } }
        var label: String { startKey + " – " + endKey }
        var maximumTokens: Int { days.map { $0.totals.tokens }.max() ?? 0 }

        /// Four blue steps share one scale for the entire visible date range.
        func intensity(for day: Bucket) -> Int {
            guard day.totals.hasTokenData, maximumTokens > 0 else { return 0 }
            return min(4, max(1, Int(ceil(Double(day.totals.tokens) / Double(maximumTokens) * 4))))
        }
    }

    struct Breakdown: Identifiable {
        struct Key: Hashable { let projectID: String; let agent: String }
        let id: Key
        let projectName: String
        let totals: Totals
    }

    let rows: [ProjectUsageStore.Row]
    let todayKey: String
    let calendar: Calendar
    var monthKey: String { String(todayKey.prefix(7)) }
    var yearKey: String { String(todayKey.prefix(4)) }
    var firstRecordedDay: String? { rows.map(\.day).min() }
    var lastRecordedDay: String? { rows.map(\.day).max() }
    var today: Totals { totals(in: todayKey) }
    var thisMonth: Totals { totals(in: monthKey) }
    var lifetime: Totals { Totals(rows: rows) }
    var months: [String] { Set(rows.map { String($0.day.prefix(7)) } + [monthKey]).sorted(by: >) }
    var years: [String] { Set(rows.map { String($0.day.prefix(4)) } + [yearKey]).sorted(by: >) }

    init(rows: [ProjectUsageStore.Row], now: Date = Date(), calendar: Calendar = .current) {
        // Persisted keys are Gregorian local dates, even with a different macOS calendar.
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.timeZone = calendar.timeZone
        self.calendar = gregorian
        todayKey = PetCare.dayKey(for: now, calendar: gregorian)
        let today = todayKey
        self.rows = rows.filter {
            $0.tokens >= 0 && $0.sessions >= 0 && ($0.tokens > 0 || $0.sessions > 0)
                && $0.day <= today && Self.date(for: $0.day, calendar: gregorian) != nil
        }
    }

    func records(in period: String) -> [ProjectUsageStore.Row] {
        rows.filter { $0.day == period || $0.day.hasPrefix(period + "-") }
    }

    func totals(in period: String) -> Totals { Totals(rows: records(in: period)) }

    func buckets(grain: Grain, period: String) -> [Bucket] {
        let key = grain == .daily ? period + "-01" : period + "-01-01"
        guard let start = Self.date(for: key, calendar: calendar) else { return [] }
        let count = grain == .daily ? (calendar.range(of: .day, in: .month, for: start)?.count ?? 0) : 12
        let component: Calendar.Component = grain == .daily ? .day : .month
        return (0..<count).compactMap { offset in
            guard let date = calendar.date(byAdding: component, value: offset, to: start) else { return nil }
            let day = PetCare.dayKey(for: date, calendar: calendar)
            guard day <= todayKey else { return nil } // Do not draw future dates as zero usage.
            let id = grain == .daily ? day : String(day.prefix(7))
            return Bucket(id: id, label: String(offset + 1), totals: totals(in: id))
        }
    }

    /// A trailing three-month calendar ending today, or at the selected past
    /// month's end. Calendar arithmetic, rather than 24-hour steps, handles DST.
    func heatmap(endingIn month: String) -> Heatmap? {
        guard month <= monthKey,
              let monthStart = Self.date(for: month + "-01", calendar: calendar),
              let nextMonth = calendar.date(byAdding: .month, value: 1, to: monthStart),
              let monthEnd = calendar.date(byAdding: .day, value: -1, to: nextMonth),
              let today = Self.date(for: todayKey, calendar: calendar) else { return nil }
        let end = min(monthEnd, today)
        guard let afterEnd = calendar.date(byAdding: .day, value: 1, to: end),
              let start = calendar.date(byAdding: .month, value: -3, to: afterEnd),
              let firstMonday = calendar.date(byAdding: .day,
                value: -((calendar.component(.weekday, from: start) + 5) % 7), to: start) else { return nil }
        let startKey = PetCare.dayKey(for: start, calendar: calendar)
        let endKey = PetCare.dayKey(for: end, calendar: calendar)
        let windowRows = rows.filter { $0.day >= startKey && $0.day <= endKey }
        let totalsByDay = Dictionary(grouping: windowRows, by: \.day).mapValues { Totals(rows: $0) }
        var weeks: [Heatmap.Week] = []
        var markers: [Int: Heatmap.MonthMarker] = [:]
        var monday = firstMonday
        while monday <= end {
            let column = weeks.count
            let days: [Bucket?] = (0..<7).map { offset in
                guard let date = calendar.date(byAdding: .day, value: offset, to: monday),
                      date >= start, date <= end else { return nil }
                let key = PetCare.dayKey(for: date, calendar: calendar)
                if date == start || calendar.component(.day, from: date) == 1 {
                    // If a short partial month shares a column with the next
                    // month, show the new month instead of overlapping labels.
                    markers[column] = .init(id: String(key.prefix(7)), column: column, date: date)
                }
                return Bucket(id: key, label: String(calendar.component(.day, from: date)),
                              totals: totalsByDay[key] ?? Totals())
            }
            weeks.append(.init(id: PetCare.dayKey(for: monday, calendar: calendar), days: days))
            guard let next = calendar.date(byAdding: .day, value: 7, to: monday) else { break }
            monday = next
        }
        return Heatmap(startKey: startKey, endKey: endKey, timeZone: calendar.timeZone, weeks: weeks,
                       months: markers.values.sorted { $0.column < $1.column }, totals: Totals(rows: windowRows))
    }

    func breakdown(in heatmap: Heatmap) -> [Breakdown] {
        breakdown(rows: rows.filter { $0.day >= heatmap.startKey && $0.day <= heatmap.endKey })
    }

    func breakdown(in period: String) -> [Breakdown] {
        breakdown(rows: records(in: period))
    }

    private func breakdown(rows: [ProjectUsageStore.Row]) -> [Breakdown] {
        let groups = Dictionary(grouping: rows) {
            Breakdown.Key(projectID: $0.projectId, agent: $0.agent)
        }
        return groups.map { key, records in
            // Prefer the latest stored folder name; custom names are resolved by the view.
            Breakdown(id: key, projectName: records.max(by: { $0.day < $1.day })?.projectName ?? "",
                      totals: Totals(rows: records))
        }.sorted {
            if $0.totals.tokens != $1.totals.tokens { return $0.totals.tokens > $1.totals.tokens }
            if $0.id.agent != $1.id.agent { return $0.id.agent < $1.id.agent }
            return $0.id.projectID < $1.id.projectID
        }
    }

    private static func date(for key: String, calendar: Calendar) -> Date? {
        let parts = key.split(separator: "-")
        guard parts.count == 3, key.count == 10,
              let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2]),
              let date = calendar.date(from: DateComponents(year: year, month: month, day: day)),
              PetCare.dayKey(for: date, calendar: calendar) == key else { return nil }
        return date
    }
}
