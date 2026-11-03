import Foundation
import Testing
@testable import agentpet
@testable import AgentPetCore

@MainActor
@Suite(.serialized)
struct CompletionNoticeTests {
    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)
    private let codexID = "00000000-0000-4000-8000-000000000001"

    private func session(_ id: String = "isolated-synthetic-a", kind: AgentKind = .codex,
                         state: AgentState = .done, project: String? = "/isolated/project") -> AgentSession {
        AgentSession(id: id, agentKind: kind, project: project, title: "隔离测试会话",
                     state: state, source: .hook, updatedAt: t0, stateSince: t0)
    }

    @Test func completionSurvivesIdleAndSessionRemoval() {
        let live = SessionStore()
        let done = live.apply(AgentEvent(sessionId: codexID, agentKind: .codex,
                                        eventName: "Stop", timestamp: t0), now: t0)!
        let reminders = CompletionNoticeStore()
        reminders.record(done, at: t0)
        live.prune(now: t0.addingTimeInterval(40))
        #expect(live.sorted.first?.state == .idle)
        reminders.refreshMetadata(from: live.sorted)
        live.prune(now: t0.addingTimeInterval(1000))
        #expect(live.sorted.isEmpty)
        reminders.refreshMetadata(from: [])
        #expect(reminders.notices.count == 1)
        #expect(reminders.notices.first?.target.sessionID == codexID)
    }

    @Test func onlyRealCompletedHookSessionsCreateNotices() {
        let store = CompletionNoticeStore()
        for state in [AgentState.registered, .working, .waiting, .idle] {
            store.record(session(state: state), at: t0)
        }
        var passive = session(); passive.source = .passive
        store.record(passive, at: t0)
        #expect(store.notices.isEmpty)
    }

    @Test func duplicateCompletionDoesNotReappearAfterDismissal() throws {
        let store = CompletionNoticeStore()
        store.record(session(), at: t0)
        store.record(session(), at: t0)
        #expect(store.notices.count == 1)
        store.dismiss(try #require(store.notices.first?.id))
        store.record(session(), at: t0)
        store.record(session(), at: t0.addingTimeInterval(-1))
        #expect(store.notices.isEmpty)
        store.record(session(), at: t0.addingTimeInterval(1))
        #expect(store.notices.count == 1)
    }

    @Test func newWorkClearsOnlyItsOwnCompletion() {
        let store = CompletionNoticeStore()
        store.record(session("a"), at: t0)
        store.record(session("b"), at: t0)
        store.observeActivity(session("a", state: .working), at: t0.addingTimeInterval(2))
        #expect(store.notices.map(\.target.sessionID) == ["b"])
        store.record(session("a"), at: t0.addingTimeInterval(1))
        #expect(store.notices.map(\.target.sessionID) == ["b"], "Late completion from an earlier turn must not return")
    }

    @Test func waitingIsNotCompletionAndOldActivityDoesNotEraseNewerDone() {
        let store = CompletionNoticeStore()
        store.record(session(), at: t0)
        store.observeActivity(session(state: .working), at: t0.addingTimeInterval(-1))
        store.observeActivity(session(state: .registered), at: t0.addingTimeInterval(1))
        store.observeActivity(session(state: .idle), at: t0.addingTimeInterval(1))
        #expect(store.notices.count == 1)
        store.observeActivity(session(state: .waiting), at: t0.addingTimeInterval(2))
        #expect(store.notices.isEmpty)
    }

    @Test func simultaneousClientsAndProjectsDoNotOverwriteEachOther() {
        let store = CompletionNoticeStore()
        store.record(session("same", kind: .codex, project: "/a"), at: t0)
        store.record(session("same", kind: .claude, project: "/b"), at: t0)
        store.record(session("other", project: "/a"), at: t0.addingTimeInterval(1))
        #expect(store.notices.count == 3)
        #expect(store.notices.first?.target.sessionID == "other")
    }

    @Test func remindersAndDismissalsSurviveRestartWithoutWritingUsageRecords() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("isolated-completion-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("reminders.json")
        let first = CompletionNoticeStore(fileURL: file)
        first.record(session(), at: t0)
        let second = CompletionNoticeStore(fileURL: file)
        #expect(second.notices == first.notices)
        second.dismiss(try #require(second.notices.first?.id))
        let third = CompletionNoticeStore(fileURL: file)
        third.record(session(), at: t0)
        #expect(third.notices.isEmpty)
        #expect(try FileManager.default.contentsOfDirectory(atPath: root.path) == ["reminders.json"])
    }

    @Test func corruptedStateReportsAnErrorRatherThanInventingCompletions() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("isolated-completion-\(UUID()).json")
        defer { try? FileManager.default.removeItem(at: file) }
        try Data("not a state file".utf8).write(to: file)
        let store = CompletionNoticeStore(fileURL: file)
        #expect(store.notices.isEmpty)
        #expect(store.persistenceError != nil)
    }

    @Test func failedSaveKeepsTheVisibleReminderAndReportsIt() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("isolated-completion-\(UUID())")
        defer { try? FileManager.default.removeItem(at: file) }
        try Data().write(to: file)
        let store = CompletionNoticeStore(fileURL: file.appendingPathComponent("not-a-directory.json"))
        store.record(session(), at: t0)
        #expect(store.notices.count == 1)
        #expect(store.persistenceError != nil)
    }

    @Test func lateMetadataPreservesNoticeIdentityAndNavigationSnapshot() throws {
        let store = CompletionNoticeStore()
        var completed = session(); completed.title = nil; completed.terminalProgram = "Apple_Terminal"
        completed.terminalTTY = "/dev/ttys001"
        store.record(completed, at: t0)
        let original = try #require(store.notices.first)
        var later = session(state: .idle); later.title = "后来取得的会话标题"
        store.refreshMetadata(from: [later])
        let updated = try #require(store.notices.first)
        #expect(updated.id == original.id)
        #expect(updated.target.title == "后来取得的会话标题")
        #expect(updated.target.terminalTTY == "/dev/ttys001")
    }

    @Test func successfulNavigationReceivesTheExactSnapshotAndAcknowledgesOnlyThatNotice() async throws {
        let store = CompletionNoticeStore()
        store.record(session("a"), at: t0)
        store.record(session("b"), at: t0.addingTimeInterval(1))
        let notice = try #require(store.notices.first)
        await store.open(notice.id) { target in
            #expect(target == notice.target)
            return .openedConversation
        }
        #expect(store.notices.map(\.target.sessionID) == ["a"])
        #expect(store.openingIDs.isEmpty)
    }

    @Test func failureUnsupportedAndAppOnlyNavigationKeepReminders() async throws {
        let store = CompletionNoticeStore()
        store.record(session(), at: t0)
        let id = try #require(store.notices.first?.id)
        for result in [SessionNavigationResult.failed, .unavailable, .applicationOnly] {
            await store.open(id) { _ in result }
            #expect(store.notices.first?.id == id)
            #expect(store.messages[id] != nil)
            #expect(store.openingIDs.isEmpty)
        }
    }

    @Test func anOlderNavigationCannotDismissTheNextCompletedTurn() async throws {
        let store = CompletionNoticeStore()
        store.record(session(), at: t0)
        let oldID = try #require(store.notices.first?.id)
        var release: CheckedContinuation<SessionNavigationResult, Never>?
        let task = Task {
            await store.open(oldID) { _ in await withCheckedContinuation { release = $0 } }
        }
        while release == nil { await Task.yield() }
        store.observeActivity(session(state: .working), at: t0.addingTimeInterval(1))
        store.record(session(), at: t0.addingTimeInterval(2))
        let newID = try #require(store.notices.first?.id)
        release?.resume(returning: .openedConversation)
        await task.value
        #expect(store.notices.first?.id == newID)
        #expect(newID != oldID)
    }

    @Test func duplicateClicksDoNotLaunchTwoNavigations() async throws {
        let store = CompletionNoticeStore()
        store.record(session(), at: t0)
        let id = try #require(store.notices.first?.id)
        var release: CheckedContinuation<SessionNavigationResult, Never>?
        let task = Task { await store.open(id) { _ in await withCheckedContinuation { release = $0 } } }
        while release == nil { await Task.yield() }
        await store.open(id) { _ in Issue.record("Duplicate navigation"); return .failed }
        release?.resume(returning: .openedConversation)
        await task.value
        #expect(store.notices.isEmpty)
    }

    @Test func projectRemindersKeepTheCorrectPetWindowAfterPruning() {
        let store = CompletionNoticeStore()
        store.record(session(project: "/work/project/subdir"), at: t0)
        let mapping = ProjectPetMapping(projectPath: "/work/project", petID: "isolated-pet")
        let planned = store.planningSessions(live: [])
        let specs = PetWindowPlanner.plan(sessions: planned, split: true, mappings: [mapping],
                                          defaultPetID: "default", hideIdleProjects: true)
        #expect(specs.contains { $0.key == "/work/project" })
        #expect(store.notices(forWindow: "/work/project", split: true, mappings: [mapping]).count == 1)
        #expect(store.notices(forWindow: PetWindowPlanner.defaultKey, split: true, mappings: [mapping]).isEmpty)
        #expect(store.notices(forWindow: PetWindowPlanner.defaultKey, split: false, mappings: [mapping]).count == 1)
        #expect(store.notices(forWindow: PetWindowPlanner.defaultKey, split: true, mappings: []).count == 1)
    }

    @Test func planningReplacesOnlyIdleSnapshotsAndDoesNotDuplicateLiveSessions() {
        let store = CompletionNoticeStore()
        store.record(session(), at: t0)
        #expect(store.planningSessions(live: [session(state: .idle)]).map(\.state) == [.done])
        #expect(store.planningSessions(live: [session(state: .done)]).count == 1)
        #expect(store.planningSessions(live: [session(state: .working)]).map(\.state) == [.working])
    }

    @Test func explicitClearRemovesNoticesButDoesNotResurrectDuplicateEvents() {
        let store = CompletionNoticeStore()
        store.record(session("a"), at: t0); store.record(session("b"), at: t0)
        store.removeSession("a")
        #expect(store.notices.map(\.target.sessionID) == ["b"])
        store.dismissAll()
        store.record(session("b"), at: t0)
        #expect(store.notices.isEmpty)
    }

    @Test func codexDesktopUsesExistingConversationURLWithoutStartingNewWork() {
        let target = SessionNavigationTarget(session(codexID))
        #expect(SessionNavigator.destination(for: target) == .conversationURL(
            URL(string: "codex://threads/\(codexID)")!, bundleID: "com.openai.codex"))
        #expect(SessionNavigator.destination(for: SessionNavigationTarget(session("not-a-thread-id"))) == .unavailable)
    }

    @Test func codexInATerminalKeepsItsOriginalTerminalInsteadOfOpeningDesktop() {
        var value = session(codexID); value.terminalProgram = "Apple_Terminal"; value.terminalTTY = "/dev/ttys003"
        #expect(SessionNavigator.destination(for: SessionNavigationTarget(value)) == .terminal(program: "Apple_Terminal", tty: "/dev/ttys003"))
        value.terminalTTY = nil
        #expect(SessionNavigator.destination(for: SessionNavigationTarget(value)) == .application(bundleID: "com.apple.Terminal"))
        value.terminalProgram = "vscode"
        #expect(SessionNavigator.destination(for: SessionNavigationTarget(value)) == .application(bundleID: "com.microsoft.VSCode"))
    }

    @Test func warpCanNavigateWithoutATermProgramButUnsupportedClientsAreHonest() {
        var value = session(kind: .claude); value.terminalFocusURL = "warp://session/isolated-pane"
        #expect(SessionNavigator.destination(for: SessionNavigationTarget(value)) == .conversationURL(URL(string: value.terminalFocusURL!)!, bundleID: "dev.warp.Warp-Stable"))
        value.terminalFocusURL = nil
        #expect(SessionNavigator.destination(for: SessionNavigationTarget(value)) == .unavailable)
        value.agentKind = .cursor
        #expect(SessionNavigator.destination(for: SessionNavigationTarget(value)) == .applicationNamed("Cursor"))
    }

    @Test func exactTerminalScriptsMustReportWhetherTheTabWasFound() throws {
        for program in ["Apple_Terminal", "iTerm.app"] {
            let script = try #require(TerminalFocus.script(program: program, tty: "/dev/ttys001"))
            #expect(script.contains("return true"))
            #expect(script.contains("return false"))
        }
        #expect(TerminalFocus.script(program: "unknown", tty: "/dev/ttys001") == nil)
        #expect(TerminalFocus.script(program: "Apple_Terminal", tty: "") == nil)
    }

    @Test func subagentCompletionDoesNotFinishItsParentTask() {
        for (kind, start, stop) in [(AgentKind.codex, "UserPromptSubmit", "SubagentStop"),
                                    (.cursor, "beforeSubmitPrompt", "subagentStop")] {
            let store = SessionStore()
            store.apply(AgentEvent(sessionId: "isolated-parent", agentKind: kind, eventName: start, timestamp: t0), now: t0)
            let nested = store.apply(AgentEvent(sessionId: "isolated-parent", agentKind: kind, eventName: stop, timestamp: t0), now: t0)
            #expect(nested == nil)
            #expect(store.sorted.first?.state == .working)
        }
    }

    @Test func completionUIAndNavigationErrorsAreLocalizedInChinese() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let bundle = try #require(Bundle(path: root.appendingPathComponent("Localizations/zh-Hans.lproj").path))
        #expect(bundle.localizedString(forKey: "Done ✅", value: nil, table: nil) == "干完了 ✅")
        #expect(String(format: bundle.localizedString(forKey: "%d tasks are done", value: nil, table: nil), 2) == "有 2 个任务干完了")
        for key in ["Open the completed conversation", "Completed conversations", "Dismiss this completion reminder",
                    "This client has not provided a conversation location. Reminder kept."] {
            #expect(bundle.localizedString(forKey: key, value: nil, table: nil) != key)
        }
    }
}
