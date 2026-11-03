import Testing
import Foundation
@testable import AgentPetCore

/// Custom CLI agents hooked via `agentpet hook --agent <name>` must keep their
/// own identity instead of masquerading as Claude or collapsing together
/// (issue #56). These lock the three pieces that make that work: the flag →
/// kind/name resolution, the sticky carry-through in the store, and the
/// grouping key the bubble dedups on.
@Suite(.serialized)
final class CustomAgentTests {
    private let now = Date(timeIntervalSince1970: 1_000_000)

    // MARK: - makeEvent flag resolution

    @Test func testUnrecognizedAgentBecomesUnknownAndKeepsRawName() throws {
        let args = HookArguments(event: "working", session: "s1", agent: "hermes")
        let event = try #require(args.makeEvent(now: now))
        #expect((event.agentKind) == (.unknown))
        #expect((event.agentName) == ("hermes"))
    }

    @Test func testMissingAgentStillDefaultsToClaude() throws {
        // Claude's hooks omit `--agent`; that legacy default must not change.
        let args = HookArguments(event: "Stop", session: "s1", agent: nil)
        let event = try #require(args.makeEvent(now: now))
        #expect((event.agentKind) == (.claude))
        #expect((event.agentName) == nil)
    }

    @Test func testRecognizedAgentMapsToItsKindWithoutRawName() throws {
        let args = HookArguments(event: "working", session: "s1", agent: "codex")
        let event = try #require(args.makeEvent(now: now))
        #expect((event.agentKind) == (.codex))
        #expect((event.agentName) == nil)
    }

    // MARK: - Grouping key

    @Test func testDistinctCustomAgentsGetDistinctGroupKeys() {
        let hermes = session(name: "hermes")
        let openclaw = session(name: "openclaw")
        #expect((hermes.groupKey) == ("unknown:hermes"))
        #expect((hermes.groupKey) != (openclaw.groupKey))
    }

    @Test func testSameCustomAgentSharesGroupKeyCaseInsensitively() {
        #expect((session(name: "Hermes").groupKey) == (session(name: "hermes").groupKey))
    }

    @Test func testKnownKindGroupsByKindNotName() {
        let s = AgentSession(id: "x", agentKind: .claude, state: .working,
                             source: .hook, updatedAt: now)
        #expect((s.groupKey) == ("claude"))
    }

    // MARK: - Sticky carry-through in the store

    @Test func testStoreCarriesAndKeepsCustomAgentName() throws {
        let store = SessionStore()
        _ = store.apply(HookArguments(event: "working", session: "s1", agent: "hermes")
            .makeEvent(now: now)!, now: now)
        // A later event for the same session omits the name (only the first
        // event carries it); it must stay sticky, not reset to nil.
        let updated = try #require(store.apply(AgentEvent(sessionId: "s1", agentKind: .unknown,
                                   eventName: "done", timestamp: now),
                        now: now.addingTimeInterval(1)))
        #expect((updated.agentName) == ("hermes"))
        #expect((updated.groupKey) == ("unknown:hermes"))
    }

    private func session(name: String) -> AgentSession {
        AgentSession(id: name, agentKind: .unknown, state: .working,
                     source: .hook, updatedAt: now, agentName: name)
    }
}
