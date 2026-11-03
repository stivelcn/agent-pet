import Testing
import Foundation
@testable import AgentPetCore

@Suite(.serialized)
final class TickerFormatterTests {

    // MARK: agentLabel

    @Test func testAgentLabelKnownKinds() {
        #expect((TickerFormatter.agentLabel(for: .claude)) == ("Claude"))
        #expect((TickerFormatter.agentLabel(for: .cursor)) == ("Cursor"))
        #expect((TickerFormatter.agentLabel(for: .codex)) == ("Codex"))
        #expect((TickerFormatter.agentLabel(for: .gemini)) == ("Gemini"))
        #expect((TickerFormatter.agentLabel(for: .opencode)) == ("Opencode"))
        #expect((TickerFormatter.agentLabel(for: .windsurf)) == ("Windsurf"))
        #expect((TickerFormatter.agentLabel(for: .antigravity)) == ("Antigravity"))
    }

    @Test func testAgentLabelFallbacks() {
        #expect((TickerFormatter.agentLabel(for: .cli)) == ("Agent"))
        #expect((TickerFormatter.agentLabel(for: .unknown)) == ("Agent"))
    }

    // MARK: line(for:)

    @Test func testLineWithMessage() {
        let session = AgentSession(
            id: "claude-abc",
            agentKind: .claude,
            project: "/Users/me/agentpet",
            state: .working,
            message: "running bash…",
            source: .hook,
            updatedAt: Date()
        )
        #expect((TickerFormatter.line(for: session)) == ("Claude [agentpet] → running bash…"))
    }

    @Test func testLineWithoutMessage() {
        let session = AgentSession(
            id: "cursor-xyz",
            agentKind: .cursor,
            project: "/Users/me/my-api",
            state: .waiting,
            message: nil,
            source: .hook,
            updatedAt: Date()
        )
        #expect((TickerFormatter.line(for: session)) == ("Cursor [my-api] → Waiting"))
    }

    @Test func testLineWithWhitespaceOnlyMessage() {
        let session = AgentSession(
            id: "gemini-1",
            agentKind: .gemini,
            project: "/Users/me/frontend",
            state: .working,
            message: "   ",
            source: .hook,
            updatedAt: Date()
        )
        #expect((TickerFormatter.line(for: session)) == ("Gemini [frontend] → Working"))
    }

    @Test func testLineFallsBackToIdWhenNoProject() {
        let session = AgentSession(
            id: "my-session-id",
            agentKind: .cli,
            project: nil,
            state: .working,
            message: "running",
            source: .hook,
            updatedAt: Date()
        )
        #expect((TickerFormatter.line(for: session)) == ("Agent [my-session-id] → running"))
    }

    // MARK: sorted(_:)

    @Test func testSortedWaitingFirst() {
        let t = Date()
        let working = AgentSession(id: "a", agentKind: .claude, state: .working, source: .hook, updatedAt: t)
        let waiting = AgentSession(id: "b", agentKind: .cursor, state: .waiting, source: .hook, updatedAt: t)
        let done    = AgentSession(id: "c", agentKind: .codex,  state: .done,    source: .hook, updatedAt: t)

        let result = TickerFormatter.sorted([done, working, waiting])
        #expect((result.map(\.id)) == (["b", "a", "c"]))
    }

    @Test func testSortedWorkingByMostRecentFirst() {
        let t0 = Date(timeIntervalSince1970: 0)
        let t1 = Date(timeIntervalSince1970: 10)
        let older = AgentSession(id: "old",   agentKind: .claude, state: .working, source: .hook, updatedAt: t0)
        let newer = AgentSession(id: "newer", agentKind: .cursor, state: .working, source: .hook, updatedAt: t1)

        let result = TickerFormatter.sorted([older, newer])
        #expect((result.first?.id) == ("newer"), Comment(rawValue: "most recently updated working agent comes first"))
    }
}
