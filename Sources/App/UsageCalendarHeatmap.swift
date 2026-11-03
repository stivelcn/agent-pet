import SwiftUI

/// Presentation only: every colored cell comes from the existing local ledger.
struct UsageCalendarHeatmap: View {
    let calendar: UsageHistoryReport.Heatmap
    let todayKey: String
    let locale: Locale
    @Binding var selectedDay: String?
    @State private var hoveredDay: String?

    private let gap: CGFloat = 7
    private let weekdayWidth: CGFloat = 30
    private let monthHeight: CGFloat = 26
    private static let colors: [Color] = [
        Color(red: 0.28, green: 0.30, blue: 0.37),
        Color(red: 0.83, green: 0.91, blue: 1.00),
        Color(red: 0.60, green: 0.78, blue: 1.00),
        Color(red: 0.33, green: 0.64, blue: 0.97),
        Color(red: 0.08, green: 0.52, blue: 0.91),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Daily activity").font(.headline)
                    Text(verbatim: calendar.label).font(.caption).foregroundStyle(Theme.muted)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 6) {
                    Text(verbatim: tokenLabel(calendar.totals)).font(.callout.monospacedDigit())
                    Text("Past three months").font(.caption).foregroundStyle(Theme.muted)
                }
            }
            grid
            HStack(spacing: 8) {
                hoverDetails
                Spacer(minLength: 8)
                legend
            }
            .font(.caption)
            Text("Each square is a day. Darker blue means more token; gray means no recorded token data, not zero usage.")
                .font(.caption).foregroundStyle(Theme.muted)
        }
        .themedCard()
        .onChange(of: calendar.endKey) { _ in hoveredDay = nil }
        .accessibilityIdentifier("usage-calendar-heatmap")
    }

    private var grid: some View {
        HStack(alignment: .top, spacing: gap) {
            ForEach(Array(calendar.weeks.enumerated()), id: \.element.id) { column, week in
                VStack(spacing: gap) {
                    ForEach(0..<7, id: \.self) { row in
                        if let day = week.days[row] {
                            cell(day)
                        } else {
                            // Before the range and after today are empty space,
                            // never gray "missing data" or interactive buttons.
                            Color.clear.aspectRatio(1, contentMode: .fit)
                                .accessibilityHidden(true)
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                .overlay(alignment: .bottomLeading) {
                    if let month = calendar.months.first(where: { $0.column == column }) {
                        Text(verbatim: monthLabel(month.date))
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Theme.muted)
                            .fixedSize()
                            .offset(y: monthHeight)
                    }
                }
            }
        }
        .padding(.leading, weekdayWidth)
        .padding(.bottom, monthHeight + 4)
        .overlay(alignment: .topLeading) {
            GeometryReader { geometry in
                let height = (geometry.size.height - monthHeight - 4 - gap * 6) / 7
                VStack(spacing: gap) {
                    ForEach(Array(weekdayLabels.enumerated()), id: \.offset) { _, label in
                        Text(verbatim: label)
                            .font(.system(size: 10))
                            .foregroundStyle(Theme.muted)
                            .frame(width: weekdayWidth - gap, height: max(0, height))
                    }
                }
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
        .frame(maxWidth: 680)
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private func cell(_ day: UsageHistoryReport.Bucket) -> some View {
        let selected = selectedDay == day.id
        let hovered = hoveredDay == day.id
        let today = day.id == todayKey
        return Button {
            selectedDay = selected ? nil : day.id
        } label: {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Self.colors[calendar.intensity(for: day)])
                .overlay {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(.white.opacity(selected ? 1 : hovered ? 0.8 : today ? 0.4 : 0),
                                      lineWidth: selected ? 2.5 : 1.5)
                        .padding(selected ? 2 : 0)
                }
                .aspectRatio(1, contentMode: .fit)
                .contentShape(RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
        .onHover { inside in
            if inside { hoveredDay = day.id }
            else if hoveredDay == day.id { hoveredDay = nil }
        }
        .help(day.id + " · " + tokenLabel(day.totals))
        .accessibilityLabel(day.id + " · " + tokenLabel(day.totals))
        .accessibilityValue(selected ? NSLocalizedString("Selected day", comment: "heatmap selection") : "")
        .accessibilityIdentifier("usage-day-" + day.id)
    }

    @ViewBuilder
    private var hoverDetails: some View {
        if let key = hoveredDay ?? selectedDay, let day = calendar.days.first(where: { $0.id == key }) {
            Text(verbatim: day.id + " · " + tokenLabel(day.totals))
                .monospacedDigit().lineLimit(1).minimumScaleFactor(0.8)
                .accessibilityIdentifier("usage-day-preview")
        } else {
            Text("Hover for usage · Click for details")
                .foregroundStyle(Theme.muted).lineLimit(1).minimumScaleFactor(0.8)
        }
    }

    private var legend: some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 3).fill(Self.colors[0]).frame(width: 12, height: 12)
            Text("No token record").padding(.trailing, 7)
            Text("Less usage")
            ForEach(1...4, id: \.self) { level in
                RoundedRectangle(cornerRadius: 3).fill(Self.colors[level]).frame(width: 12, height: 12)
            }
            Text("More usage")
        }
        .foregroundStyle(Theme.muted)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Blue intensity represents token usage")
    }

    private var weekdayLabels: [String] {
        let formatter = DateFormatter()
        formatter.locale = locale
        let labels = formatter.shortWeekdaySymbols ?? ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
        return Array(labels.dropFirst()) + [labels[0]]
    }

    private func monthLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = calendar.timeZone
        formatter.setLocalizedDateFormatFromTemplate("MMM")
        return formatter.string(from: date)
    }

    private func tokenLabel(_ totals: UsageHistoryReport.Totals) -> String {
        totals.hasTokenData
            ? totals.tokens.formatted(.number.locale(locale)) + " token"
            : NSLocalizedString("No recorded token data", comment: "missing data")
    }
}
