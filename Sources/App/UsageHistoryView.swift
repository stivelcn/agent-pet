import SwiftUI
import AgentPetCore

struct UsageHistoryView: View {
    @ObservedObject var store: ProjectUsageStore
    @ObservedObject private var language = AppLanguage.shared
    @ObservedObject private var pet = PetController.shared
    @ObservedObject private var imagePets = ImagePetStore.shared
    @ObservedObject private var care = PetCareController.shared
    @ObservedObject private var projectNames = ProjectNameStore.shared
    @State private var grain: UsageHistoryReport.Grain = .daily
    @State private var selectedMonth: String
    @State private var selectedYear: String
    @State private var selectedBucket: String?

    init(store: ProjectUsageStore) {
        self.store = store
        let report = UsageHistoryReport(rows: [])
        _selectedMonth = State(initialValue: report.monthKey)
        _selectedYear = State(initialValue: report.yearKey)
    }

    private var period: String { grain == .daily ? selectedMonth : selectedYear }
    private var detailPeriod: String { selectedBucket ?? period }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            let report = UsageHistoryReport(rows: store.recordedRows(), now: context.date)
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    summary(report)
                    periodControls(report)
                    trend(report)
                    breakdown(report)
                    periodTable(report)
                    companion
                    coverage(report)
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .background(Theme.background)
        .environment(\.colorScheme, .dark)
        .environment(\.locale, language.locale)
        .onChange(of: grain) { _ in selectedBucket = nil }
        .onChange(of: selectedMonth) { _ in selectedBucket = nil }
        .onChange(of: selectedYear) { _ in selectedBucket = nil }
        .accessibilityIdentifier("usage-history-content")
    }

    private var header: some View {
        HStack(spacing: 14) {
            if let id = pet.selectedPetID, let frame = imagePets.pack(id: id)?.restingFrames.first {
                Image(nsImage: frame).resizable().interpolation(.none)
                    .scaledToFit().frame(width: 56, height: 56)
                    .accessibilityHidden(true)
            } else {
                Image(systemName: "chart.bar.xaxis").font(.system(size: 30))
                    .foregroundStyle(Theme.accent).frame(width: 56, height: 56)
            }
            VStack(alignment: .leading, spacing: 5) {
                Text("token usage statistics").font(.system(size: 25, weight: .bold))
                Text(verbatim: imagePets.displayName(for: pet.selectedPetID))
                    .font(.callout).foregroundStyle(Theme.muted)
            }
            Spacer()
            Label("Local · Auto-updating", systemImage: "externaldrive")
                .font(.caption).foregroundStyle(Theme.muted)
        }
    }

    private func summary(_ report: UsageHistoryReport) -> some View {
        HStack(spacing: 12) {
            metric("Today token", value: tokenLabel(report.today), exact: exactTokenLabel(report.today))
            metric("This month token", value: tokenLabel(report.thisMonth), exact: exactTokenLabel(report.thisMonth))
            metric("Recorded token total", value: tokenLabel(report.lifetime), exact: exactTokenLabel(report.lifetime))
            metric("Recorded completions", value: report.lifetime.hasRecords ? number(report.lifetime.completions) : "—",
                   exact: NSLocalizedString("Completion events reported by connected agents, not unique conversations.", comment: "count definition"))
        }
    }

    private func metric(_ title: String, value: String, exact: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(LocalizedStringKey(title)).font(.caption).foregroundStyle(Theme.muted)
            Text(verbatim: value).font(.system(size: 25, weight: .semibold, design: .rounded))
                .monospacedDigit().lineLimit(1).minimumScaleFactor(0.65)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .themedCard()
        .help(exact)
    }

    private func periodControls(_ report: UsageHistoryReport) -> some View {
        // Keep an explicitly selected empty period valid across midnight/month rollover.
        let months = Set(report.months + [selectedMonth]).sorted(by: >)
        let years = Set(report.years + [selectedYear]).sorted(by: >)
        return HStack(spacing: 16) {
            Picker("Time grouping", selection: $grain) {
                ForEach(UsageHistoryReport.Grain.allCases, id: \.self) { grain in
                    Text(LocalizedStringKey(grain.title)).tag(grain)
                }
            }
            .pickerStyle(.segmented).labelsHidden().frame(width: 180)
            .accessibilityIdentifier("usage-grain-picker")
            if grain == .daily {
                Picker("Ending month", selection: $selectedMonth) {
                    ForEach(months, id: \.self) { Text(verbatim: $0).tag($0) }
                }
                .frame(width: 185).accessibilityIdentifier("usage-month-picker")
            } else {
                Picker("Year", selection: $selectedYear) {
                    ForEach(years, id: \.self) { Text(verbatim: $0).tag($0) }
                }
                .frame(width: 165).accessibilityIdentifier("usage-year-picker")
            }
            Spacer()
            Text("All recorded clients").font(.caption).foregroundStyle(Theme.muted)
        }
    }

    @ViewBuilder
    private func trend(_ report: UsageHistoryReport) -> some View {
        if grain == .daily {
            if let calendar = report.heatmap(endingIn: selectedMonth) {
                UsageCalendarHeatmap(calendar: calendar, todayKey: report.todayKey,
                                     locale: language.locale, selectedDay: $selectedBucket)
            }
        } else {
            monthlyTrend(report)
        }
    }

    private func monthlyTrend(_ report: UsageHistoryReport) -> some View {
        let buckets = report.buckets(grain: grain, period: period)
        let maximum = max(buckets.map { $0.totals.tokens }.max() ?? 0, 1)
        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("token trend").font(.headline)
                Text(verbatim: period).font(.callout).foregroundStyle(Theme.muted)
                Spacer()
                Text(verbatim: exactTokenLabel(report.totals(in: period)))
                    .font(.callout.monospacedDigit())
            }
            HStack(alignment: .bottom, spacing: 12) {
                ForEach(buckets) { bucket in
                    Button {
                        select(bucket.id)
                    } label: {
                        VStack(spacing: 7) {
                            ZStack(alignment: .bottom) {
                                RoundedRectangle(cornerRadius: 4).fill(Color.white.opacity(0.025))
                                if bucket.totals.hasTokenData {
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(selectedBucket == bucket.id ? Color.cyan : Theme.accent)
                                        .frame(height: max(3, 112 * Double(bucket.totals.tokens) / Double(maximum)))
                                } else {
                                    Text("—").font(.system(size: 10)).foregroundStyle(Theme.muted)
                                        .padding(.bottom, 2)
                                }
                            }
                            .frame(height: 112)
                            Text(verbatim: bucket.label).font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(selectedBucket == bucket.id ? .white : Theme.muted)
                        }
                        .frame(maxWidth: .infinity)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(bucket.id + " · " + exactTokenLabel(bucket.totals))
                    .accessibilityLabel(bucket.id + " · " + exactTokenLabel(bucket.totals))
                    .accessibilityIdentifier("usage-bucket-" + bucket.id)
                }
            }
            Text("Click a bar or date to inspect its clients and projects. — means no recorded token data, not zero usage.")
                .font(.caption).foregroundStyle(Theme.muted)
        }
        .themedCard()
    }

    private func breakdown(_ report: UsageHistoryReport) -> some View {
        let calendar = grain == .daily ? report.heatmap(endingIn: selectedMonth) : nil
        let rows: [UsageHistoryReport.Breakdown]
        if let calendar, selectedBucket == nil {
            rows = report.breakdown(in: calendar)
        } else {
            rows = report.breakdown(in: detailPeriod)
        }
        let label = selectedBucket ?? calendar?.label ?? period
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Clients and projects").font(.headline)
                Text(verbatim: label).font(.caption).foregroundStyle(Theme.muted)
                Spacer()
                if selectedBucket != nil {
                    Button("Show entire period") { selectedBucket = nil }.buttonStyle(.link)
                }
            }
            if rows.isEmpty {
                emptyState
            } else {
                HStack {
                    Text("Client / Project")
                    Spacer()
                    Text(verbatim: "token").frame(width: 150, alignment: .trailing)
                    Text("Completions").frame(width: 80, alignment: .trailing)
                }
                .font(.caption).foregroundStyle(Theme.muted)
                ForEach(rows) { row in
                    Divider().overlay(Color.white.opacity(0.06))
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(verbatim: agentName(row.id.agent)).font(.callout.weight(.semibold))
                            Text(verbatim: projectName(row)).font(.caption).foregroundStyle(Theme.muted)
                                .lineLimit(1).help(projectName(row))
                        }
                        Spacer()
                        Text(verbatim: row.totals.hasTokenData ? number(row.totals.tokens) : "—")
                            .frame(width: 150, alignment: .trailing)
                        Text(verbatim: number(row.totals.completions)).frame(width: 80, alignment: .trailing)
                    }
                    .font(.callout.monospacedDigit()).textSelection(.enabled)
                }
            }
        }
        .themedCard()
    }

    private func periodTable(_ report: UsageHistoryReport) -> some View {
        let buckets = grain == .daily
            ? report.heatmap(endingIn: selectedMonth)?.days ?? []
            : report.buckets(grain: grain, period: period)
        return VStack(alignment: .leading, spacing: 10) {
            Text(LocalizedStringKey(grain == .daily ? "Daily details" : "Monthly details")).font(.headline)
            HStack {
                Text("Date")
                Spacer()
                Text(verbatim: "token").frame(width: 150, alignment: .trailing)
                Text("Completions").frame(width: 80, alignment: .trailing)
            }
            .font(.caption).foregroundStyle(Theme.muted)
            LazyVStack(spacing: 0) {
                ForEach(buckets.reversed()) { bucket in
                    Button {
                        select(bucket.id)
                    } label: {
                        HStack {
                            Text(verbatim: bucket.id)
                            if !bucket.totals.hasRecords {
                                Text("No records").font(.caption).foregroundStyle(Theme.muted)
                            }
                            Spacer()
                            Text(verbatim: bucket.totals.hasTokenData ? number(bucket.totals.tokens) : "—")
                                .frame(width: 150, alignment: .trailing)
                            Text(verbatim: bucket.totals.hasRecords ? number(bucket.totals.completions) : "—")
                                .frame(width: 80, alignment: .trailing)
                        }
                        .font(.callout.monospacedDigit())
                        .padding(.vertical, 9).padding(.horizontal, 6)
                        .background(selectedBucket == bucket.id ? Theme.accent.opacity(0.18) : .clear)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    Divider().overlay(Color.white.opacity(0.04))
                }
            }
        }
        .themedCard()
    }

    private var companion: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Companion growth", systemImage: "pawprint.fill").font(.headline)
                Spacer()
                Text(verbatim: imagePets.displayName(for: pet.selectedPetID)).foregroundStyle(Theme.muted)
            }
            HStack(spacing: 24) {
                Text(String(format: NSLocalizedString("Pet received %@ token", comment: "pet lifetime"), number(care.current.totalTokens)))
                Text(String(format: NSLocalizedString("Pet meals: %@", comment: "pet lifetime"), number(care.current.totalMeals)))
            }
            .font(.callout.monospacedDigit())
            Text("Pet growth belongs to this companion only. Usage statistics above cover all locally recorded clients; their totals may differ.")
                .font(.caption).foregroundStyle(Theme.muted)
        }
        .themedCard()
    }

    private func coverage(_ report: UsageHistoryReport) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if let first = report.firstRecordedDay, let last = report.lastRecordedDay {
                Text(String(format: NSLocalizedString("Recorded dates: %@ – %@", comment: "available history"), first, last))
            }
            Text("Only locally collected usage is shown, not a provider bill or your full account history. Previously deleted or uncollected records cannot be recovered here. Daily and monthly aggregates are kept locally going forward.")
            Text("Some clients report completions without token counts. — means unavailable. Completion counts track reported task-finished events, not unique conversations.")
        }
        .font(.caption).foregroundStyle(Theme.muted)
        .textSelection(.enabled)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "chart.bar.xaxis").font(.title2).foregroundStyle(Theme.muted)
            Text("No usage records in this period")
            Text("Use a connected agent as usual. Reported usage will appear here automatically; no manual import is needed.")
                .font(.caption).foregroundStyle(Theme.muted)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 16)
    }

    private func select(_ key: String) { selectedBucket = selectedBucket == key ? nil : key }
    private func number(_ value: Int) -> String { value.formatted(.number.locale(language.locale)) }
    private func tokenLabel(_ totals: UsageHistoryReport.Totals) -> String {
        totals.hasTokenData ? CareFormat.tokens(totals.tokens) : "—"
    }
    private func exactTokenLabel(_ totals: UsageHistoryReport.Totals) -> String {
        totals.hasTokenData ? number(totals.tokens) + " token" : NSLocalizedString("No recorded token data", comment: "missing data")
    }
    private func projectName(_ row: UsageHistoryReport.Breakdown) -> String {
        if row.id.projectID == ProjectUsageStore.unassignedProjectID {
            return NSLocalizedString("Unknown project", comment: "missing project metadata")
        }
        let custom = projectNames.customName(forID: row.id.projectID)
        return custom.isEmpty ? row.projectName : custom
    }
    private func agentName(_ id: String) -> String {
        if id == "cli" { return NSLocalizedString("Coding agent", comment: "generic agent") }
        if id == "unknown" { return NSLocalizedString("Other agents", comment: "unknown agent") }
        return AgentUsage.label(for: id)
    }
}
