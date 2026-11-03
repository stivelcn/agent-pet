import Testing
import Foundation
@testable import AgentPetCore

@Suite(.serialized)
final class AgentUsageTests {
    private typealias R = AgentUsage.Record

    @Test func testTotalsSumTodayAndMonthPerAgent() {
        let rows = [
            R(agent: "claude", day: "2026-10-20", tokens: 100, sessions: 1),
            R(agent: "claude", day: "2026-10-03", tokens: 400, sessions: 2),
            R(agent: "codex",  day: "2026-10-20", tokens: 50,  sessions: 0),
        ]
        let t = AgentUsage.totals(rows, today: "2026-10-20")
        #expect((t) == ([
            AgentUsageTotal(agent: "claude", today: 100, month: 500, sessions: 3),
            AgentUsageTotal(agent: "codex",  today: 50,  month: 50,  sessions: 0),
        ]))
    }

    @Test func testOtherMonthsAreLeftOut() {
        let rows = [
            R(agent: "claude", day: "2026-09-30", tokens: 999, sessions: 5),
            R(agent: "codex",  day: "2026-10-01", tokens: 10,  sessions: 0),
        ]
        #expect((AgentUsage.totals(rows, today: "2026-10-20").map(\.agent)) == (["codex"]))
    }

    @Test func testSortsByMonthTokensThenName() {
        let rows = [
            R(agent: "b", day: "2026-10-01", tokens: 5, sessions: 0),
            R(agent: "a", day: "2026-10-01", tokens: 5, sessions: 0),
            R(agent: "z", day: "2026-10-01", tokens: 9, sessions: 0),
        ]
        #expect((AgentUsage.totals(rows, today: "2026-10-20").map(\.agent)) == (["z", "a", "b"]))
    }

    /// An agent whose hook carries no token counts still shows its finished sessions.
    @Test func testSessionOnlyAgentIsKeptAndEmptyOneDropped() {
        let rows = [
            R(agent: "grok", day: "2026-10-02", tokens: 0, sessions: 3),
            R(agent: "ghost", day: "2026-10-02", tokens: 0, sessions: 0),
        ]
        let t = AgentUsage.totals(rows, today: "2026-10-20")
        #expect((t.map(\.agent)) == (["grok"]))
        #expect((t.first?.sessions) == (3))
    }

    @Test func testLabels() {
        #expect((AgentUsage.label(for: "jcode")) == ("jcode"))
        #expect((AgentUsage.label(for: "claude")) == ("Claude"))
        #expect((AgentUsage.label(for: "kiroCLI")) == ("Kiro"))
        #expect((AgentUsage.label(for: "cli")) == ("Agent"))
        #expect((AgentUsage.label(for: "mybot")) == ("Mybot"))
    }

    // MARK: - Storage key (custom agents must not merge into one row)

    @Test func testKeyIsTheKindForKnownAgents() {
        #expect((AgentUsage.key(kind: .claude, agentName: nil)) == ("claude"))
        #expect((AgentUsage.key(kind: .jcode, agentName: "ignored")) == ("jcode"))
    }

    @Test func testKeyIsTheRawNameForCustomAgents() {
        #expect((AgentUsage.key(kind: .unknown, agentName: "mybot")) == ("mybot"))
        #expect((AgentUsage.key(kind: .unknown, agentName: "  mybot \n")) == ("mybot"))
        #expect((AgentUsage.key(kind: .unknown, agentName: "a")) != (AgentUsage.key(kind: .unknown, agentName: "b")))
    }

    @Test func testKeyFallsBackToUnknownWithoutAName() {
        #expect((AgentUsage.key(kind: .unknown, agentName: nil)) == ("unknown"))
        #expect((AgentUsage.key(kind: .unknown, agentName: "   ")) == ("unknown"))
    }

    @Test func testUnnamedCustomAgentIsLabelledOther() {
        #expect((AgentUsage.label(for: "unknown")) == ("Other"))
        #expect((AgentUsage.label(for: AgentUsage.key(kind: .unknown, agentName: "mybot"))) == ("Mybot"))
    }

    // MARK: - Session-only rows

    @Test func testSessionOnlyMeansNoTokensButSessions() {
        #expect(AgentUsage.isSessionOnly(AgentUsageTotal(agent: "grok", today: 0, month: 0, sessions: 3)))
        #expect(!(AgentUsage.isSessionOnly(AgentUsageTotal(agent: "grok", today: 0, month: 5, sessions: 3))))
        #expect(!(AgentUsage.isSessionOnly(AgentUsageTotal(agent: "grok", today: 0, month: 0, sessions: 0))))
    }
}
