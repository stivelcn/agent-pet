import AppKit
import Combine
import Foundation
import Testing
@testable import agentpet

/// All records in this suite are explicitly synthetic and live only in a
/// disposable preferences suite. Never seed or overwrite the user's history.
@MainActor
@Suite(.serialized)
struct UsageHistoryTests {
    private var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return cal
    }
    private func date(_ value: String) -> Date {
        ISO8601DateFormatter().date(from: value)!
    }
    private var now: Date { date("2026-11-03T12:00:00+08:00") }
    private func row(_ day: String, tokens: Int = 100, sessions: Int = 1,
                     project: String = "synthetic-p1", agent: String = "codex") -> ProjectUsageStore.Row {
        .init(projectId: project, projectName: "Synthetic project", agent: agent,
              day: day, tokens: tokens, sessions: sessions)
    }
    private func report(_ rows: [ProjectUsageStore.Row]) -> UsageHistoryReport {
        UsageHistoryReport(rows: rows, now: now, calendar: calendar)
    }
    private func withDefaults(_ action: (UserDefaults) throws -> Void) rethrows {
        let suite = "local.agentpet.tests.usageHistory." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        try action(defaults)
    }

    @Test func dayMonthAndLifetimeUseTheSameRealLedgerWithoutDoubleCounting() {
        let r = report([
            row("2025-11-03", tokens: 4), row("2026-10-31", tokens: 10),
            row("2026-11-01", tokens: 20), row("2026-11-03", tokens: 30),
            row("2026-11-03", tokens: 40, project: "synthetic-p2", agent: "claude"),
        ])
        #expect(r.today.tokens == 70)
        #expect(r.thisMonth.tokens == 90)
        #expect(r.lifetime.tokens == 104)
        #expect(r.lifetime.completions == 5)
        #expect(r.months == ["2026-11", "2026-10", "2025-11"])
        #expect(r.years == ["2026", "2025"])
        #expect(r.firstRecordedDay == "2025-11-03")
        #expect(r.lastRecordedDay == "2026-11-03")
    }

    @Test func dailyBucketsKeepGapsUnknownAndExcludeFutureDays() {
        let r = report([row("2026-11-03", tokens: 350)])
        let bins = r.buckets(grain: .daily, period: "2026-11")
        #expect(bins.map(\.id) == ["2026-11-01", "2026-11-02", "2026-11-03"])
        #expect(!bins[0].totals.hasRecords)
        #expect(!bins[0].totals.hasTokenData)
        #expect(bins[2].totals.tokens == 350)
        #expect(bins.reduce(0) { $0 + $1.totals.tokens } == r.thisMonth.tokens)
    }

    @Test func monthlyBucketsAggregateAcrossProjectsAndRespectYearBoundaries() {
        let r = report([
            row("2025-11-03", tokens: 900), row("2026-01-01", tokens: 10),
            row("2026-11-01", tokens: 20), row("2026-11-03", tokens: 30, project: "synthetic-p2"),
        ])
        let bins = r.buckets(grain: .monthly, period: "2026")
        #expect(bins.count == 11)
        #expect(bins.first?.totals.tokens == 10)
        #expect(bins.last?.totals.tokens == 50)
        #expect(bins.reduce(0) { $0 + $1.totals.tokens } == 60)
        #expect(r.buckets(grain: .monthly, period: "2025").count == 12)
    }

    @Test func leapFebruaryHasTwentyNineDaysAndInvalidPeriodsAreEmpty() {
        let r = report([row("2024-02-29", tokens: 29)])
        let bins = r.buckets(grain: .daily, period: "2024-02")
        #expect(bins.count == 29)
        #expect(bins.last?.id == "2024-02-29")
        #expect(bins.last?.totals.tokens == 29)
        #expect(r.buckets(grain: .daily, period: "2025-02").count == 28)
        #expect(r.buckets(grain: .daily, period: "2026-13").isEmpty)
        #expect(r.buckets(grain: .monthly, period: "invalid").isEmpty)
    }

    @Test func invalidNegativeAndFutureRowsCannotPolluteTotals() {
        let r = report([
            row("2026-11-03", tokens: 3), row("2026-11-04", tokens: 400),
            row("2026-02-30", tokens: 500), row("2026-1-02", tokens: 500),
            row("2026-01-01", tokens: -30), row("2026-01-02", sessions: -1),
        ])
        #expect(r.rows.count == 1)
        #expect(r.lifetime.tokens == 3)
    }

    @Test func sessionOnlyClientsHaveCountsButNoFabricatedZeroTokenValue() {
        let r = report([row("2026-11-03", tokens: 0, sessions: 5, agent: "cursor")])
        #expect(r.today.hasRecords)
        #expect(!r.today.hasTokenData)
        #expect(r.today.completions == 5)
        #expect(r.breakdown(in: "2026-11").first?.totals.hasTokenData == false)
    }

    @Test func breakdownUsesProjectIdentityNotDisplayNameAndSupportsDayDrilldown() {
        let r = report([
            row("2026-11-01", tokens: 10), row("2026-11-03", tokens: 20),
            row("2026-11-03", tokens: 40, project: "synthetic-p2"),
            row("2026-11-03", tokens: 80, agent: "claude"),
        ])
        let groups = r.breakdown(in: "2026-11")
        #expect(groups.count == 3)
        #expect(groups.map { $0.totals.tokens } == [80, 40, 30])
        #expect(r.breakdown(in: "2026-11-03").map { $0.totals.tokens } == [80, 40, 20])
        #expect(r.breakdown(in: "2026-10").isEmpty)
    }

    @Test func emptyHistoryHasNoInventedCoverageOrTokenData() {
        let r = report([])
        #expect(r.firstRecordedDay == nil)
        #expect(r.lastRecordedDay == nil)
        #expect(!r.lifetime.hasRecords)
        #expect(!r.today.hasTokenData)
        #expect(r.months == ["2026-11"])
        #expect(r.years == ["2026"])
        #expect(r.buckets(grain: .daily, period: "2026-11").allSatisfy { !$0.totals.hasRecords })
    }

    @Test func localMidnightAndNewYearRecomputeWithoutNewEvents() {
        let rows = [row("2026-12-31", tokens: 123)]
        let before = UsageHistoryReport(rows: rows, now: date("2026-12-31T23:59:59+08:00"), calendar: calendar)
        let after = UsageHistoryReport(rows: rows, now: date("2027-01-01T00:00:01+08:00"), calendar: calendar)
        #expect(before.today.tokens == 123)
        #expect(!after.today.hasRecords)
        #expect(!after.thisMonth.hasRecords)
        #expect(after.lifetime.tokens == 123)
        #expect(after.yearKey == "2027")
    }

    @Test func daylightSavingMonthStillContainsEachCalendarDayOnce() {
        var cal = calendar
        cal.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let r = UsageHistoryReport(rows: [], now: date("2026-12-01T12:00:00-08:00"), calendar: cal)
        let bins = r.buckets(grain: .daily, period: "2026-11")
        #expect(bins.count == 30)
        #expect(Set(bins.map(\.id)).count == 30)
        #expect(bins.first?.id == "2026-11-01")
        #expect(bins.last?.id == "2026-11-30")
    }

    @Test func nonGregorianSystemCalendarDoesNotChangeStoredDateKeys() {
        var cal = Calendar(identifier: .buddhist)
        cal.timeZone = calendar.timeZone
        let r = UsageHistoryReport(rows: [row("2026-11-03")], now: now, calendar: cal)
        #expect(r.todayKey == "2026-11-03")
        #expect(r.today.tokens == 100)
    }

    @Test func historicalRowsOlderThanOneHundredTwentyDaysSurviveReloadUnchanged() throws {
        try withDefaults { defaults in
            let old = row("2024-02-29", tokens: 12345)
            let data = try JSONEncoder().encode(["synthetic-p1|codex|2024-02-29": old])
            defaults.set(data, forKey: "agentpet.projectUsage")
            let store = ProjectUsageStore(defaults: defaults, now: { now }, calendar: calendar)
            #expect(store.recordedRows() == [old])
            #expect(defaults.data(forKey: "agentpet.projectUsage") == data)
            store.recordTokens(10, project: "/synthetic/new", agent: "codex")
            let restored = ProjectUsageStore(defaults: defaults, now: { now }, calendar: calendar)
            #expect(restored.recordedRows().count == 2)
            #expect(restored.recordedRows().contains(old))
        }
    }

    @Test func missingProjectMetadataStillRecordsUsageAndStaysOutOfProjectSettings() {
        withDefaults { defaults in
            let store = ProjectUsageStore(defaults: defaults, now: { now }, calendar: calendar)
            store.recordTokens(10, project: nil, agent: "codex")
            store.recordTokens(20, project: "  ", agent: "codex")
            store.recordSession(project: "", agent: "codex")
            let rows = store.recordedRows()
            #expect(rows.count == 1)
            #expect(rows.first?.projectId == ProjectUsageStore.unassignedProjectID)
            #expect(rows.first?.tokens == 30)
            #expect(rows.first?.sessions == 1)
            #expect(store.knownProjects().isEmpty)
        }
    }

    @Test func recordingPublishesLiveUpdatesAndPersistsAcrossRestarts() {
        withDefaults { defaults in
            let store = ProjectUsageStore(defaults: defaults, now: { now }, calendar: calendar)
            var changes = 0
            let subscription = store.objectWillChange.sink { changes += 1 }
            store.recordTokens(200, project: "/synthetic/p", agent: "codex")
            store.recordSession(project: "/synthetic/p", agent: "codex")
            #expect(changes > 0)
            let restored = ProjectUsageStore(defaults: defaults, now: { now }, calendar: calendar)
            #expect(restored.recordedRows() == store.recordedRows())
            #expect(restored.recordedRows().first?.tokens == 200)
            #expect(restored.recordedRows().first?.sessions == 1)
            subscription.cancel()
        }
    }

    @Test func recordingAcrossMidnightCreatesSeparateDailyRows() {
        withDefaults { defaults in
            var clock = date("2026-11-03T23:59:59+08:00")
            let store = ProjectUsageStore(defaults: defaults, now: { clock }, calendar: calendar)
            store.recordTokens(10, project: "/synthetic/p", agent: "codex")
            clock = date("2026-11-04T00:00:01+08:00")
            store.recordTokens(20, project: "/synthetic/p", agent: "codex")
            #expect(store.recordedRows().map(\.day) == ["2026-11-03", "2026-11-04"])
            #expect(store.byAgent().first?.today == 20)
            #expect(store.byAgent().first?.month == 30)
        }
    }

    @Test func invalidRecordingCannotSubtractUsage() {
        withDefaults { defaults in
            let store = ProjectUsageStore(defaults: defaults, now: { now }, calendar: calendar)
            store.recordTokens(-1, project: "/synthetic/p", agent: "codex")
            store.recordTokens(50, project: "/synthetic/p", agent: "  ")
            #expect(store.recordedRows().isEmpty)
            store.recordTokens(10, project: "/synthetic/p", agent: "codex")
            store.recordTokens(20, project: "/synthetic/p", agent: "codex")
            #expect(store.recordedRows().first?.tokens == 30)
            let restored = ProjectUsageStore(defaults: defaults, now: { now }, calendar: calendar)
            #expect(restored.recordedRows().first?.tokens == 30)
        }
    }

    @Test func heatmapShowsThreeMonthsThroughTodayWithMondayFirstWeeks() throws {
        let map = try #require(report([]).heatmap(endingIn: "2026-11"))
        #expect(map.startKey == "2026-08-04")
        #expect(map.endKey == "2026-11-03")
        #expect(map.days.count == 92)
        #expect(map.weeks.count == 14)
        #expect(map.weeks.allSatisfy { $0.days.count == 7 })
        #expect(map.weeks.first?.id == "2026-08-03")
        #expect(map.weeks.first?.days[0] == nil)
        #expect(map.weeks.first?.days[1]?.id == "2026-08-04")
        #expect(map.weeks.last?.days[1]?.id == "2026-11-03")
        #expect(map.weeks.last?.days.dropFirst(2).allSatisfy { $0 == nil } == true)
        #expect(Set(map.days.map(\.id)).count == map.days.count)
    }

    @Test func heatmapHistoricalMonthAndDetailsUseExactlyTheVisibleRange() throws {
        let r = report([
            row("2026-07-31", tokens: 900), row("2026-08-01", tokens: 10),
            row("2026-09-01", tokens: 20, agent: "claude"),
            row("2026-10-31", tokens: 30), row("2026-11-01", tokens: 800),
        ])
        let map = try #require(r.heatmap(endingIn: "2026-10"))
        #expect(map.startKey == "2026-08-01")
        #expect(map.endKey == "2026-10-31")
        #expect(map.totals.tokens == 60)
        #expect(map.totals.completions == 3)
        #expect(map.days.reduce(0) { $0 + $1.totals.tokens } == map.totals.tokens)
        #expect(r.breakdown(in: map).reduce(0) { $0 + $1.totals.tokens } == map.totals.tokens)
        #expect(r.breakdown(in: "2026-10-31").first?.totals.tokens == 30)
    }

    @Test func heatmapBlueScaleIsMonotonicAndSharedAcrossClients() throws {
        let r = report([
            row("2026-11-01", tokens: 1), row("2026-11-02", tokens: 40),
            row("2026-11-03", tokens: 50), row("2026-11-03", tokens: 50, agent: "claude"),
        ])
        let map = try #require(r.heatmap(endingIn: "2026-11"))
        #expect(map.maximumTokens == 100)
        let active = map.days.filter { $0.totals.hasTokenData }
        #expect(active.map { map.intensity(for: $0) } == [1, 2, 4])
        #expect(map.days.allSatisfy { (0...4).contains(map.intensity(for: $0)) })
        #expect(map.intensity(for: try #require(map.days.first)) == 0)
    }

    @Test func heatmapMissingTokenCountsRemainGrayEvenWithCompletions() throws {
        let r = report([row("2026-11-03", tokens: 0, sessions: 5, agent: "cursor")])
        let map = try #require(r.heatmap(endingIn: "2026-11"))
        let day = try #require(map.days.last)
        #expect(day.totals.hasRecords)
        #expect(!day.totals.hasTokenData)
        #expect(day.totals.completions == 5)
        #expect(map.intensity(for: day) == 0)
        #expect(map.maximumTokens == 0)
        #expect(!map.totals.hasTokenData)
    }

    @Test func emptyHeatmapKeepsRealCalendarWithoutInventingUsage() throws {
        let map = try #require(report([]).heatmap(endingIn: "2026-11"))
        #expect(!map.totals.hasRecords)
        #expect(map.days.count > 80)
        #expect(map.days.allSatisfy { !$0.totals.hasRecords && map.intensity(for: $0) == 0 })
        #expect(map.months.map(\.id) == ["2026-08", "2026-09", "2026-10", "2026-11"])
        #expect(Set(map.months.map(\.column)).count == map.months.count)
        #expect(map.months.allSatisfy { map.weeks.indices.contains($0.column) })
    }

    @Test func heatmapHandlesLeapDayAndUsesFullHistoricalCalendarMonths() throws {
        let r = report([row("2024-02-29", tokens: 29)])
        let map = try #require(r.heatmap(endingIn: "2024-02"))
        #expect(map.startKey == "2023-12-01")
        #expect(map.endKey == "2024-02-29")
        #expect(map.days.count == 91)
        #expect(map.days.last?.totals.tokens == 29)
        #expect(map.months.map(\.id) == ["2023-12", "2024-01", "2024-02"])
        #expect(r.heatmap(endingIn: "2025-02")?.days.count == 90)
    }

    @Test func heatmapRejectsMalformedAndFuturePeriods() {
        let r = report([])
        for invalid in ["2026-12", "2027-01", "2026-13", "2026-1", "", "invalid"] {
            #expect(r.heatmap(endingIn: invalid) == nil)
        }
    }

    @Test func heatmapMidnightAndNewYearMoveTheWindowWithoutNewEvents() throws {
        let rows = [row("2026-12-31", tokens: 20)]
        let before = UsageHistoryReport(rows: rows, now: date("2026-12-31T23:59:59+08:00"), calendar: calendar)
        let after = UsageHistoryReport(rows: rows, now: date("2027-01-01T00:00:01+08:00"), calendar: calendar)
        let a = try #require(before.heatmap(endingIn: before.monthKey))
        let b = try #require(after.heatmap(endingIn: after.monthKey))
        #expect(a.startKey == "2026-10-01")
        #expect(b.startKey == "2026-10-02")
        #expect(b.endKey == "2027-01-01")
        #expect(b.days.last?.totals.hasRecords == false)
        #expect(a.totals.tokens == b.totals.tokens)
    }

    @Test func heatmapDaylightSavingDoesNotSkipDuplicateOrShiftWeekdays() throws {
        var cal = calendar
        cal.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        for month in ["2026-03", "2026-11"] {
            let r = UsageHistoryReport(rows: [], now: date("2026-12-01T12:00:00-08:00"), calendar: cal)
            let map = try #require(r.heatmap(endingIn: month))
            #expect(map.timeZone == cal.timeZone)
            #expect(Set(map.days.map(\.id)).count == map.days.count)
            for week in map.weeks {
                for (offset, day) in week.days.enumerated() {
                    if let day {
                        let parts = day.id.split(separator: "-").compactMap { Int($0) }
                        let value = try #require(cal.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2])))
                        #expect((cal.component(.weekday, from: value) + 5) % 7 == offset)
                    }
                }
            }
            #expect(map.days.count == (month == "2026-03" ? 90 : 91))
        }
    }

    @Test func heatmapEveryMonthEndAlignsPaddingAndNeverLeaksFutureDates() throws {
        for month in 1...12 {
            let monthKey = String(format: "2024-%02d", month)
            let r = UsageHistoryReport(rows: [], now: date("2025-01-01T12:00:00+08:00"), calendar: calendar)
            let map = try #require(r.heatmap(endingIn: monthKey))
            #expect(map.days.first?.id == map.startKey)
            #expect(map.days.last?.id == map.endKey)
            #expect(map.days.allSatisfy { $0.id >= map.startKey && $0.id <= map.endKey })
            #expect(map.days.map(\.id) == map.days.map(\.id).sorted())
            #expect((13...14).contains(map.weeks.count))
        }
    }

    @Test func chineseCopyKeepsTokenAndTranslatesMenuSections() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let path = root.appendingPathComponent("Localizations/zh-Hans.lproj/Localizable.strings")
        let strings = try #require(NSDictionary(contentsOf: path) as? [String: String])
        #expect(strings.values.allSatisfy { !$0.contains("词元") && !$0.contains("詞元") })
        #expect(strings["Today %@ tokens · %d meals"]?.contains("token") == true)
        #expect(strings["Companion"] == "伙伴")
        #expect(strings["Agents"] == "编程助手")
        #expect(strings["token usage statistics"] == "token 用量统计")
        #expect(strings["By day"] == "按日")
        #expect(strings["By month"] == "按月")
        #expect(strings["Ending month"] == "截至月份")
        #expect(strings["Daily activity"] == "每日用量")
        #expect(strings["Hover for usage · Click for details"] == "悬停查看用量 · 点击查看明细")
    }
}

@MainActor
@Suite(.serialized)
struct UsageHistoryWindowTests {
    @Test func repeatedOpeningReusesWindowAndClosingAllowsFreshReopen() async throws {
        _ = NSApplication.shared
        let suite = "local.agentpet.tests.usageWindow." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let controller = UsageHistoryWindowController(store: ProjectUsageStore(defaults: defaults))
        defer { controller.window?.close() }
        controller.show()
        let first = try #require(controller.window)
        #expect(first.identifier?.rawValue == "usage-history-window")
        #expect(first.styleMask.contains(.resizable))
        #expect(first.contentMinSize.width >= 760)
        controller.show()
        #expect(ObjectIdentifier(try #require(controller.window)) == ObjectIdentifier(first))
        try await Task.sleep(for: .milliseconds(250))
        #expect(first.isVisible)
        first.close()
        #expect(controller.window == nil)
        controller.show()
        #expect(ObjectIdentifier(try #require(controller.window)) != ObjectIdentifier(first))
    }

    @Test func closingStatisticsDoesNotDeactivateAnotherOpenAppWindow() throws {
        _ = NSApplication.shared
        let otherOwner = UUID()
        AppWindowActivation.acquire(otherOwner)
        defer { AppWindowActivation.release(otherOwner) }
        let suite = "local.agentpet.tests.usageWindow." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let controller = UsageHistoryWindowController(store: ProjectUsageStore(defaults: defaults))
        controller.show()
        let window = try #require(controller.window)
        window.close()
        #expect(NSApp.activationPolicy() == .regular)
        AppWindowActivation.release(otherOwner)
        #expect(NSApp.activationPolicy() == .accessory)
    }
}
