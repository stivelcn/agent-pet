import Testing
import Foundation
@testable import AgentPetCore

@Suite(.serialized)
final class StateMapperTests {
    @Test func testClaudeEventMapping() {
        #expect((StateMapper.state(for: .claude, eventName: "SessionStart")) == (.registered))
        #expect((StateMapper.state(for: .claude, eventName: "UserPromptSubmit")) == (.working))
        #expect((StateMapper.state(for: .claude, eventName: "PreToolUse")) == (.working))
        #expect((StateMapper.state(for: .claude, eventName: "PostToolUse")) == (.working))
        #expect((StateMapper.state(for: .claude, eventName: "Notification")) == (.waiting))
        #expect((StateMapper.state(for: .claude, eventName: "Stop")) == (.done))
        #expect((StateMapper.state(for: .claude, eventName: "SubagentStop")) == nil, Comment(rawValue: "a subagent finishing mid-task must not change the main session's state"))
    }

    @Test func testUnknownEventIsIgnored() {
        #expect((StateMapper.state(for: .claude, eventName: "Bogus")) == nil)
        #expect((StateMapper.state(for: .codex, eventName: "Bogus")) == nil)
        #expect((StateMapper.state(for: .unknown, eventName: "Stop")) == nil)
    }

    @Test func testDirectStateNameMapsForAnyKind() {
        #expect((StateMapper.state(for: .cli, eventName: "working")) == (.working))
        #expect((StateMapper.state(for: .cli, eventName: "done")) == (.done))
        #expect((StateMapper.state(for: .unknown, eventName: "waiting")) == (.waiting))
    }

    @Test func testCodexMapping() {
        #expect((StateMapper.state(for: .codex, eventName: "SessionStart")) == (.registered))
        #expect((StateMapper.state(for: .codex, eventName: "PreToolUse")) == (.working))
        #expect((StateMapper.state(for: .codex, eventName: "PermissionRequest")) == (.waiting))
        #expect((StateMapper.state(for: .codex, eventName: "Stop")) == (.done))
    }

    @Test func testGeminiMapping() {
        #expect((StateMapper.state(for: .gemini, eventName: "BeforeTool")) == (.working))
        #expect((StateMapper.state(for: .gemini, eventName: "Notification")) == (.waiting))
        #expect((StateMapper.state(for: .gemini, eventName: "AfterAgent")) == (.done))
    }

    @Test func testHookSpecsCoverInstallEvents() {
        // Every event we register must either map to a state, end the session,
        // or be an intentionally-ignored event (documented here).
        let intentionallyIgnored: [AgentKind: Set<String>] = [
            .claude: ["SubagentStop"],
            .codex: ["SubagentStop"]
        ]
        for kind in [AgentKind.claude, .codex, .gemini] {
            let spec = AgentHooks.spec(for: kind)!
            let ignored = intentionallyIgnored[kind] ?? []
            for event in spec.events
            where !StateMapper.isSessionEnd(for: kind, eventName: event) && !ignored.contains(event) {
                #expect((StateMapper.state(for: kind, eventName: event)) != nil, Comment(rawValue: "\(kind) \(event)"))
            }
        }
    }
}

@Suite(.serialized)
final class SessionStoreTests {
    private let t0 = Date(timeIntervalSince1970: 1_000_000)

    private func event(_ name: String, session: String = "s1", project: String? = "/proj") -> AgentEvent {
        AgentEvent(sessionId: session, agentKind: .claude, eventName: name, project: project, message: nil, timestamp: t0)
    }

    @Test func testApplyCreatesSession() {
        let store = SessionStore()
        let s = store.apply(event("SessionStart"), now: t0)
        #expect((s?.state) == (.registered))
        #expect((s?.project) == ("/proj"))
        #expect((s?.source) == (.hook))
        #expect((store.sessions.count) == (1))
    }

    @Test func testApplyUpdatesExistingAndKeepsProjectWhenNil() {
        let store = SessionStore()
        store.apply(event("SessionStart"), now: t0)
        let updated = store.apply(event("Stop", project: nil), now: t0.addingTimeInterval(5))
        #expect((updated?.state) == (.done))
        #expect((updated?.project) == ("/proj"), Comment(rawValue: "project should persist when event omits it"))
        #expect((store.sessions.count) == (1))
    }

    @Test func testApplyKeepsModelWhenLaterEventOmitsIt() {
        let store = SessionStore()
        let withModel = AgentEvent(
            sessionId: "s1", agentKind: .claude, eventName: "SessionStart",
            project: "/proj", message: nil, model: "Sonnet 4.6", timestamp: t0
        )
        store.apply(withModel, now: t0)

        let withoutModel = AgentEvent(
            sessionId: "s1", agentKind: .claude, eventName: "Stop",
            project: "/proj", message: nil, model: nil, timestamp: t0.addingTimeInterval(5)
        )
        let updated = store.apply(withoutModel, now: t0.addingTimeInterval(5))

        #expect((updated?.model) == ("Sonnet 4.6"), Comment(rawValue: "model should persist when a later event omits it"))
    }

    @Test func testApplySetsModelOnNewSession() {
        let store = SessionStore()
        let withModel = AgentEvent(
            sessionId: "s1", agentKind: .claude, eventName: "SessionStart",
            project: "/proj", message: nil, model: "Sonnet 4.6", timestamp: t0
        )
        let s = store.apply(withModel, now: t0)
        #expect((s?.model) == ("Sonnet 4.6"))
    }

    @Test func testApplySetsTerminalOnNewSession() {
        let store = SessionStore()
        let e = AgentEvent(
            sessionId: "s1", agentKind: .claude, eventName: "SessionStart",
            project: "/proj", terminalProgram: "iTerm.app", terminalTTY: "/dev/ttys003", timestamp: t0
        )
        let s = store.apply(e, now: t0)
        #expect((s?.terminalProgram) == ("iTerm.app"))
        #expect((s?.terminalTTY) == ("/dev/ttys003"))
    }

    @Test func testApplyKeepsTerminalWhenLaterEventOmitsIt() {
        let store = SessionStore()
        let withTerminal = AgentEvent(
            sessionId: "s1", agentKind: .claude, eventName: "SessionStart",
            terminalProgram: "Apple_Terminal", terminalTTY: "/dev/ttys007", timestamp: t0
        )
        store.apply(withTerminal, now: t0)

        let withoutTerminal = AgentEvent(
            sessionId: "s1", agentKind: .claude, eventName: "Stop",
            timestamp: t0.addingTimeInterval(5)
        )
        let updated = store.apply(withoutTerminal, now: t0.addingTimeInterval(5))

        #expect((updated?.terminalProgram) == ("Apple_Terminal"), Comment(rawValue: "terminal should persist across later events"))
        #expect((updated?.terminalTTY) == ("/dev/ttys007"))
    }

    @Test func testApplyIgnoresUnmappedEvent() {
        let store = SessionStore()
        #expect((store.apply(event("Bogus"), now: t0)) == nil)
        #expect((store.sessions.count) == (0))
    }

    @Test func testRefineStateAppliesWhenStateAndSinceStillMatch() {
        let store = SessionStore()
        let applied = store.apply(event("Stop"), now: t0)
        #expect((applied?.state) == (.done))

        store.refineState(id: "s1", from: .done, to: .waiting, since: applied!.stateSince)

        let refined = store.session(id: "s1")
        #expect((refined?.state) == (.waiting))
        #expect((refined?.stateSince) == (applied!.stateSince), Comment(rawValue: "correction preserves the original transition time"))
    }

    @Test func testRefineStateNoOpsWhenANewerEventAlreadyChangedState() {
        let store = SessionStore()
        let applied = store.apply(event("Stop"), now: t0)
        store.apply(event("UserPromptSubmit"), now: t0.addingTimeInterval(2))   // user replied -> working

        store.refineState(id: "s1", from: .done, to: .waiting, since: applied!.stateSince)

        #expect((store.session(id: "s1")?.state) == (.working), Comment(rawValue: "a newer transition must never be clobbered by a stale correction"))
    }

    @Test func testRefineStateNoOpsWhenSinceNoLongerMatches() {
        let store = SessionStore()
        let applied = store.apply(event("Stop"), now: t0)
        let staleSince = applied!.stateSince.addingTimeInterval(-10)

        store.refineState(id: "s1", from: .done, to: .waiting, since: staleSince)

        #expect((store.session(id: "s1")?.state) == (.done), Comment(rawValue: "a `since` mismatch means this correction targets a transition that's gone"))
    }

    @Test func testPruneDemotesDoneToIdle() {
        let store = SessionStore(doneToIdleAfter: 30, removeIdleAfter: 600)
        store.apply(event("Stop"), now: t0)
        store.prune(now: t0.addingTimeInterval(10))
        #expect((store.session(id: "s1")?.state) == (.done), Comment(rawValue: "still done before threshold"))
        store.prune(now: t0.addingTimeInterval(40))
        #expect((store.session(id: "s1")?.state) == (.idle), Comment(rawValue: "demoted to idle after threshold"))
    }

    @Test func testPruneRemovesLongIdle() {
        let store = SessionStore(doneToIdleAfter: 30, removeIdleAfter: 600)
        store.apply(event("Stop"), now: t0)
        store.prune(now: t0.addingTimeInterval(40))   // -> idle at t0+40
        store.prune(now: t0.addingTimeInterval(40 + 600))
        #expect((store.session(id: "s1")) == nil, Comment(rawValue: "removed after idle timeout"))
    }

    @Test func testPruneRemovesStaleActiveSession() {
        let store = SessionStore(staleActiveAfter: 300)
        store.apply(event("UserPromptSubmit"), now: t0)   // working
        store.prune(now: t0.addingTimeInterval(120))
        #expect((store.session(id: "s1")) != nil, Comment(rawValue: "kept before stale timeout"))
        store.prune(now: t0.addingTimeInterval(300))
        #expect((store.session(id: "s1")) == nil, Comment(rawValue: "stale working session removed"))
    }

    @Test func testPruneRemovesStaleRegisteredSooner() {
        let store = SessionStore(staleActiveAfter: 300, staleRegisteredAfter: 90)
        store.apply(event("SessionStart"), now: t0)   // registered, never worked
        store.prune(now: t0.addingTimeInterval(60))
        #expect((store.session(id: "s1")) != nil, Comment(rawValue: "kept before registered timeout"))
        store.prune(now: t0.addingTimeInterval(90))
        #expect((store.session(id: "s1")) == nil, Comment(rawValue: "idle registered session removed sooner than working"))
    }

    @Test func testClearRemovesAll() {
        let store = SessionStore()
        store.apply(event("UserPromptSubmit", session: "a"), now: t0)
        store.apply(event("UserPromptSubmit", session: "b"), now: t0)
        store.clear()
        #expect(store.sessions.isEmpty)
    }

    @Test func testSortedByAttentionPriority() {
        let store = SessionStore()
        store.apply(event("UserPromptSubmit", session: "working"), now: t0)
        store.apply(event("Notification", session: "waiting"), now: t0)
        store.apply(event("Stop", session: "done"), now: t0)
        let order = store.sorted.map(\.id)
        #expect((order) == (["working", "waiting", "done"]))
    }

    // MARK: - pendingApproval gating

    private func approvalEvent(
        requestId: String? = "req-1", toolName: String? = "Bash", toolSummary: String? = "npm test",
        session: String = "s1", at date: Date
    ) -> AgentEvent {
        AgentEvent(
            sessionId: session, agentKind: .claude, eventName: "PreToolUse", project: "/proj",
            approvalRequestId: requestId, toolName: toolName, toolSummary: toolSummary, timestamp: date
        )
    }

    @Test func testApplyWithApprovalRequestIdSetsWaitingStateAndPendingApproval() {
        let store = SessionStore()
        let s = store.apply(approvalEvent(at: t0), now: t0)
        #expect((s?.state) == (.waiting), Comment(rawValue: "a gated tool request must override the PreToolUse .working mapping"))
        #expect((s?.pendingApproval?.requestId) == ("req-1"))
        #expect((s?.pendingApproval?.toolName) == ("Bash"))
        #expect((s?.pendingApproval?.summary) == ("npm test"))
    }

    @Test func testSubsequentEventWithoutApprovalIdClearsPendingApproval() {
        let store = SessionStore()
        store.apply(approvalEvent(at: t0), now: t0)
        let updated = store.apply(event("PostToolUse"), now: t0.addingTimeInterval(1))
        #expect((updated?.pendingApproval) == nil, Comment(rawValue: "a later event with no approval request must clear a stale one"))
    }

    @Test func testSecondApprovalRequestOverwritesPendingApprovalNewestWins() {
        let store = SessionStore()
        store.apply(approvalEvent(requestId: "req-1", at: t0), now: t0)
        let second = store.apply(
            approvalEvent(requestId: "req-2", toolName: "Bash", toolSummary: "rm -rf tmp", at: t0.addingTimeInterval(1)),
            now: t0.addingTimeInterval(1)
        )
        #expect((second?.pendingApproval?.requestId) == ("req-2"), Comment(rawValue: "newest pending approval wins, it does not queue"))
        #expect((second?.pendingApproval?.summary) == ("rm -rf tmp"))
    }

    @Test func testResolveApprovalClearsPendingApprovalAndSetsWorkingWhenIdMatches() {
        let store = SessionStore()
        store.apply(approvalEvent(requestId: "req-1", at: t0), now: t0)
        let resolved = store.resolveApproval(id: "s1", requestId: "req-1")
        #expect(resolved)
        #expect((store.session(id: "s1")?.pendingApproval) == nil)
        #expect((store.session(id: "s1")?.state) == (.working))
    }

    @Test func testResolveApprovalNoOpsWhenRequestIdMismatches() {
        let store = SessionStore()
        store.apply(approvalEvent(requestId: "req-1", at: t0), now: t0)
        let resolved = store.resolveApproval(id: "s1", requestId: "wrong-id")
        #expect(!(resolved))
        #expect((store.session(id: "s1")?.pendingApproval?.requestId) == ("req-1"), Comment(rawValue: "mismatched requestId must not clear an unrelated/newer pending approval"))
        #expect((store.session(id: "s1")?.state) == (.waiting))
    }

    @Test func testResolveApprovalNoOpsWhenSessionMissing() {
        let store = SessionStore()
        #expect(!(store.resolveApproval(id: "missing", requestId: "req-1")))
    }
}
