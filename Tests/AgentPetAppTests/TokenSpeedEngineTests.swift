import Foundation
import Testing
@testable import AgentSpeedCore

/// Isolated synthetic responses verify token speed, daily accounting and local
/// reporting remain intact after removing the independent monetary metrics.
struct TokenSpeedEngineTests {
    private let day: Int64 = 1_800_000_000_000
    private var now: Int64 { day + 10_000 }

    private func response(output: Int = 60, start: Int64? = nil, end: Int64? = nil) -> ResponseRecord {
        ResponseRecord(key: "synthetic-response", source: .codex, agentId: "synthetic-agent",
                       model: "synthetic-model", startMs: start ?? day + 7_000, endMs: end ?? day + 9_000,
                       usage: TokenUsage(input: 120, output: output))
    }

    @Test func measuredTokensAndSpeedRemainExact() {
        var engine = SpeedEngine()
        engine.upsert(response(), project: "synthetic", isCompletion: true, emitsEvents: true, nowMs: now)
        let result = engine.advance(nowMs: now, todayStartMs: day, emitsEvents: false)
        #expect(result.today.total == 180)
        #expect(result.today.requests == 1)
        #expect(result.todayBySource[.codex]?.total == 180)
        #expect(result.live.output == 20)
        #expect(result.live.total == 60)
        #expect(result.averageToday == 30)
        #expect(result.liveEstimatedShare == 0)
        #expect(result.report.counters.byModel.values.reduce(0) { $0 + $1.output } == 60)
    }

    @Test func replacingAResponseDoesNotDoubleCountTokensOrRequests() {
        var engine = SpeedEngine()
        engine.upsert(response(), project: "synthetic", isCompletion: true, emitsEvents: true, nowMs: now)
        _ = engine.advance(nowMs: now, todayStartMs: day, emitsEvents: false)
        engine.upsert(response(output: 90), project: "synthetic", isCompletion: false, emitsEvents: true, nowMs: now)
        let result = engine.advance(nowMs: now, todayStartMs: day, emitsEvents: false)
        #expect(result.today.total == 210)
        #expect(result.today.requests == 1)
        #expect(result.live.output == 30)
        #expect(result.report.counters.byModel.values.reduce(0) { $0 + $1.output } == 90)
        #expect(result.report.counters.byModel.values.reduce(0) { $0 + $1.requests } == 1)
    }

    @Test func inflightTokenSpeedEstimatesDoNotBecomeRecordedUsage() {
        var engine = SpeedEngine()
        engine.upsert(response(start: day + 1_000, end: day + 3_000), project: "synthetic",
                      isCompletion: true, emitsEvents: false)
        engine.setAgent(EngineAgent(id: "synthetic-agent", source: .codex, project: "synthetic",
                                    model: "synthetic-model", phase: .generating,
                                    inFlightStartMs: day + 7_000, lastLineMs: now))
        let result = engine.advance(nowMs: now, todayStartMs: day, emitsEvents: false)
        #expect(result.live.output == 30)
        #expect(result.live.total == 90)
        #expect(result.liveEstimatedShare == 1)
        #expect(result.today.total == 180)
        #expect(result.today.requests == 1)
    }

    @Test func midnightRollsOverDailyTokensWithoutLosingStoredResponses() {
        var engine = SpeedEngine()
        engine.upsert(response(), project: "synthetic", isCompletion: true, emitsEvents: false)
        _ = engine.advance(nowMs: now, todayStartMs: day, emitsEvents: false)
        let result = engine.advance(nowMs: day + 15_000, todayStartMs: day + 12_000, emitsEvents: false)
        #expect(result.today.total == 0)
        #expect(result.today.requests == 0)
        #expect(engine.storedResponses.count == 1)
    }

    @Test func dailyAggregationPreservesModelsAndTokenCounts() throws {
        var labeler = DayLabeler(timeZone: TimeZone(secondsFromGMT: 0)!)
        let days = DayAggregate.contributions(of: [response()], source: .codex, labeler: &labeler)
        let entry = try #require(days.first)
        let usage = entry.value.usage(day: entry.key.day, source: .codex, peak: nil)
        #expect(usage.totals.total == 180)
        #expect(usage.totals.requests == 1)
        #expect(usage.models.first?.model == "synthetic-model")
        #expect(usage.models.first?.output == 60)
        #expect(usage.averageSpeed == 30)
    }

    @Test func transcriptParserStateIsAvailableForEveryFamily() {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
        for family in TranscriptFamily.allCases {
            let parser = TranscriptParser(family: family, agentId: root + "/session.jsonl", fileID: 1, root: root)
            #expect(parser.state.source == family.sources[0])
            #expect(parser.state.malformedLines == 0)
        }
    }

    @Test func transcriptParserStateReflectsUpdatesForEveryFamily() {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
        for family in TranscriptFamily.allCases {
            var parser = TranscriptParser(family: family, agentId: root + "/session.jsonl", fileID: 1, root: root)
            var expected = parser.state
            parser.noteMalformedLine()
            expected.malformedLines = 1
            #expect(parser.state == expected)
            parser.noteMalformedLine()
            expected.malformedLines = 2
            #expect(parser.state == expected)
        }
    }

    @Test func localReportingKeepsValidModelIdentifiersWithoutLookupTables() {
        #expect(ReportModelIds.canonical(" Synthetic-Model ") == "synthetic-model")
        #expect(ReportModelIds.canonical(nil) == ReportModelIds.unknown)
        #expect(ReportModelIds.canonical("/synthetic/not-a-model") == ReportModelIds.unknown)
    }
}
