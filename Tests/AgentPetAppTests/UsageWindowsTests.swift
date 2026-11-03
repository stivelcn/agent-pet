import Testing
import Foundation
@testable import agentpet

/// Per-window limits and provider hiding.
@MainActor
@Suite(.serialized)
final class UsageWindowsTests {

    private func json(_ s: String) throws -> [String: Any] { try UsageTestSupport.json(s) }

    // MARK: - Every window is kept

    @Test func testClaudeKeepsBothWindowsWithResets() throws {
        let body = try json("""
        {"five_hour": {"utilization": 37.0, "resets_at": "2026-10-02T23:59:59.536032+00:00"},
         "seven_day": {"utilization": 79.0, "resets_at": "2026-10-05T03:59:59.536051+00:00"}}
        """)
        let p = try #require(NativeUsageProbe.claudeProvider(from: body))
        #expect((p.windows.map(\.label)) == (["Session", "Weekly"]))
        #expect((p.windows.map { LimitFormat.shortLabel($0) }) == (["5h", "7d"]))
        #expect(abs((p.windows[0].fractionLeft) - (0.63)) <= 0.001)
        #expect(abs((p.windows[1].fractionLeft) - (0.21)) <= 0.001)
        #expect((p.windows[0].resetsAt) != nil)
        #expect((p.windows[1].resetsAt) != nil)
        // The summary fields still describe the tightest window.
        #expect(abs((p.fractionLeft ?? -1) - (0.21)) <= 0.001)
        #expect((p.windowLabel) == ("Weekly"))
    }

    @Test func testCodexKeepsBothWindowsWithPeriods() throws {
        let body = try json("""
        {"rate_limit": {
          "primary_window": {"used_percent": 16, "limit_window_seconds": 18000, "reset_at": 1790997688},
          "secondary_window": {"used_percent": 3, "limit_window_seconds": 604800, "reset_at": 1791584488}}}
        """)
        let p = try #require(NativeUsageProbe.codexProvider(from: body, now: Date()) { _ in nil })
        #expect((p.windows.map { LimitFormat.shortLabel($0) }) == (["5h", "7d"]))
        #expect((p.windows.compactMap(\.resetsAt).map(\.timeIntervalSince1970)) == ([1_790_997_688, 1_791_584_488]))
    }

    @Test func testOpenUsageKeepsEveryProgressLine() throws {
        let body = try json("""
        {"providerId": "antigravity", "plan": "Ultra", "lines": [
          {"type": "progress", "label": "Session", "used": 0, "limit": 100,
           "resetsAt": "2026-10-03T04:00:08.000Z", "periodDurationMs": 18000000},
          {"type": "progress", "label": "Weekly", "used": 9, "limit": 100,
           "resetsAt": "2026-10-07T02:26:05.000Z", "periodDurationMs": 604800000},
          {"type": "text", "label": "Last 30 Days", "value": "$7.96"}]}
        """)
        let p = try #require(OpenUsageClient.provider(from: body))
        #expect((p.windows.map(\.label)) == (["Session", "Weekly"]))
        #expect((p.windows.map { LimitFormat.shortLabel($0) }) == (["5h", "7d"]))
        #expect((p.windows.compactMap(\.resetsAt).count) == (2))
    }

    // MARK: - Labels

    @Test func testWindowTitle() {
        let session = OpenUsageClient.Window(label: "Session", fractionLeft: 1, period: 18000)
        let weekly = OpenUsageClient.Window(label: "Weekly limit", fractionLeft: 1, period: nil)
        let bare = OpenUsageClient.Window(label: "", fractionLeft: 1, period: 604800)
        #expect((LimitFormat.title(session)) == ("Session · 5h"))
        #expect((LimitFormat.title(weekly)) == ("Weekly limit"))
        #expect((LimitFormat.title(bare)) == ("7d"))
    }

    @Test func testShortWindowsAndEmptyLabels() {
        let tenMin = OpenUsageClient.Window(label: "Burst", fractionLeft: 1, period: 600)
        #expect((LimitFormat.shortLabel(tenMin)) == ("10m"))
        #expect((LimitFormat.title(tenMin)) == ("Burst · 10m"))
        let blank = OpenUsageClient.Window(label: "", fractionLeft: 1, period: nil)
        #expect(!(LimitFormat.title(blank).isEmpty))
    }

    @Test func testResetClockTodayThisWeekAndLater() throws {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = try #require(TimeZone(identifier: "Asia/Ho_Chi_Minh"))
        let locale = Locale(identifier: "en_GB")
        let now = try #require(ISO8601DateFormatter().date(from: "2026-10-03T06:00:00+07:00"))
        let today = now.addingTimeInterval(3 * 3600)          // Sat 09:00
        let monday = now.addingTimeInterval(2 * 86400 + 3600) // Mon 07:00
        let later = now.addingTimeInterval(29 * 86400)        // Nov 1
        #expect((LimitFormat.clock(today, now: now, calendar: cal, locale: locale)) == ("09:00"))
        #expect((LimitFormat.clock(monday, now: now, calendar: cal, locale: locale)) == ("Mon 07:00"))
        #expect((LimitFormat.clock(later, now: now, calendar: cal, locale: locale)) == ("1 Nov"))
    }

    /// The formatter is built once per template, locale and time zone, not once
    /// per row per render.
    @Test func testClockReusesFormatterPerTemplateLocaleAndZone() throws {
        var hcm = Calendar(identifier: .gregorian)
        hcm.timeZone = try #require(TimeZone(identifier: "Asia/Ho_Chi_Minh"))
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = try #require(TimeZone(identifier: "UTC"))
        let gb = Locale(identifier: "en_GB")
        let us = Locale(identifier: "en_US")

        let a = LimitFormat.formatter(template: "jmm", calendar: hcm, locale: gb)
        #expect(a === LimitFormat.formatter(template: "jmm", calendar: hcm, locale: gb))
        #expect(!(a === LimitFormat.formatter(template: "MMMd", calendar: hcm, locale: gb)))
        #expect(!(a === LimitFormat.formatter(template: "jmm", calendar: hcm, locale: us)))
        #expect(!(a === LimitFormat.formatter(template: "jmm", calendar: utc, locale: gb)))

        // Reuse must not leak one zone's output into another.
        // 12:00 and 15:00 +07:00 are 05:00 and 08:00 UTC: the same day in both zones.
        let now = try #require(ISO8601DateFormatter().date(from: "2026-10-03T12:00:00+07:00"))
        let at = now.addingTimeInterval(3 * 3600)
        #expect((LimitFormat.clock(at, now: now, calendar: hcm, locale: gb)) == ("15:00"))
        #expect((LimitFormat.clock(at, now: now, calendar: utc, locale: gb)) == ("08:00"))
        #expect((LimitFormat.clock(at, now: now, calendar: hcm, locale: gb)) == ("15:00"))
    }

    @Test func testResetTextNilWhenPastOrUnknown() {
        let now = Date()
        #expect((LimitFormat.reset(nil, now: now)) == nil)
        #expect((LimitFormat.reset(now.addingTimeInterval(-60), now: now)) == nil)
        #expect((LimitFormat.reset(now.addingTimeInterval(3 * 3600 + 60), now: now)) != nil)
        #expect((LimitFormat.compactReset(nil, now: now)) == nil)
        #expect((LimitFormat.compactReset(now.addingTimeInterval(-60), now: now)) == nil)
        #expect((LimitFormat.compactReset(now.addingTimeInterval(3600), now: now)?.hasPrefix("↻ ")) == (true))
    }

    // MARK: - Hiding providers

    @Test func testHiddenProvidersAreFilteredAndPersisted() throws {
        try UsageTestSupport.withCleanDefaults { defaults in
        let store = UsageVisibility(defaults: defaults)
        let providers = ["claude", "codex", "grok"].map { UsageTestSupport.provider($0, left: 0.5) }
        #expect((store.visible(providers).map(\.id)) == (["claude", "codex", "grok"]))

        store.setVisible("grok", false)
        #expect((store.visible(providers).map(\.id)) == (["claude", "codex"]))

        // A fresh store reads the same choice back.
        #expect((UsageVisibility(defaults: defaults).visible(providers).map(\.id)) == (["claude", "codex"]))

        store.setVisible("grok", true)
        #expect((UsageVisibility(defaults: defaults).visible(providers).map(\.id)) == (["claude", "codex", "grok"]))
        }
    }

    /// A nearly spent provider the user hid must not make the pet anxious
    /// (limitLow) or trigger the rate-limit bubble (lowestFractionLeft).
    @Test func testHiddenProviderDoesNotDriveMoodOrBubble() throws {
        try UsageTestSupport.withCleanDefaults { defaults in
        let store = UsageVisibility(defaults: defaults)
        let providers = [UsageTestSupport.provider("claude", left: 0.6),
                         UsageTestSupport.provider("grok", left: 0.05)]
        #expect(store.limitLow(providers))
        #expect(abs((store.lowestFractionLeft(providers) ?? -1) - (0.05)) <= 0.0001)
        let engine = ReactiveEngine()
        #expect((engine.evaluate(metric: .rateLimit, value: store.lowestFractionLeft(providers))) != nil)

        store.setVisible("grok", false)
        #expect(!(store.limitLow(providers)))
        #expect(abs((store.lowestFractionLeft(providers) ?? -1) - (0.6)) <= 0.0001)
        #expect((ReactiveEngine().evaluate(metric: .rateLimit, value: store.lowestFractionLeft(providers))) == nil)

        // Everything hidden: nothing to worry about.
        store.setVisible("claude", false)
        #expect(!(store.limitLow(providers)))
        #expect((store.lowestFractionLeft(providers)) == nil)
        }
    }

    /// The summary fields come from the windows: the tightest one wins, and a
    /// provider with no limit (text/badge only) has none at all.
    @Test func testSummaryFollowsTightestWindow() {
        let p = OpenUsageClient.Provider(id: "x", displayName: "X", plan: nil, todayLabel: nil, windows: [
            .init(label: "Session", fractionLeft: 0.9, resetsAt: Date(timeIntervalSince1970: 1)),
            .init(label: "Weekly", fractionLeft: 0.2, resetsAt: Date(timeIntervalSince1970: 2)),
        ])
        #expect((p.fractionLeft) == (0.2))
        #expect((p.windowLabel) == ("Weekly"))
        #expect((p.resetsAt) == (Date(timeIntervalSince1970: 2)))
        let none = OpenUsageClient.Provider(id: "y", displayName: "Y", plan: nil, todayLabel: "$3")
        #expect((none.fractionLeft) == nil)
        #expect((none.windowLabel) == nil)
        #expect((none.resetsAt) == nil)
    }
}
