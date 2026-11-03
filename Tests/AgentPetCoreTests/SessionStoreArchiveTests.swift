import Testing
import Foundation
@testable import AgentPetCore

// MARK: - Helpers

private func makeTmpArchiveStore() -> (SessionArchiveStore, URL) {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("SessionStoreArchiveTests-\(UUID().uuidString)", isDirectory: true)
    return (SessionArchiveStore(baseURL: dir), dir)
}

// MARK: - SessionStore + archiveStore Integration Tests

@Suite(.serialized)
final class SessionStoreArchiveTests {

    private let t0 = Date(timeIntervalSince1970: 1_000_000)

    private func event(
        _ name: String,
        session: String = "s1",
        project: String? = "/proj"
    ) -> AgentEvent {
        AgentEvent(
            sessionId: session,
            agentKind: .claude,
            eventName: name,
            project: project,
            message: nil,
            timestamp: t0
        )
    }

    // MARK: Test 1
    // idle session 被 prune 時，archiveStore 收到正確 sessionId、createdAt、endedAt

    @Test func testIdleSessionPruneArchivesWithCorrectTimestamps() {
        let (archiveStore, dir) = makeTmpArchiveStore()
        defer { try? FileManager.default.removeItem(at: dir) }

        let store = SessionStore(doneToIdleAfter: 30, removeIdleAfter: 60)
        store.archiveStore = archiveStore

        // working → done
        store.apply(event("PreToolUse"), now: t0)
        store.apply(event("Stop"), now: t0.addingTimeInterval(10))

        // prune: done → idle at t0+40
        store.prune(now: t0.addingTimeInterval(40))
        // prune: idle timeout → remove + archive at t0+110
        let pruneNow = t0.addingTimeInterval(110)
        store.prune(now: pruneNow)

        let records = archiveStore.records(for: t0)
        #expect((records.count) == (1), Comment(rawValue: "idle session removed by prune should be archived"))

        let record = records.first!
        #expect((record.sessionId) == ("s1"))
        // createdAt 應係 session 首次出現時（t0），endedAt 係 prune 發生時
        #expect(abs((record.startedAt.timeIntervalSince1970) - (t0.timeIntervalSince1970)) <= 1, Comment(rawValue: "startedAt should equal session createdAt"))
        #expect(abs((record.endedAt.timeIntervalSince1970) - (pruneNow.timeIntervalSince1970)) <= 1, Comment(rawValue: "endedAt should equal the prune timestamp"))
    }

    // MARK: Test 2
    // isSessionEnd 路徑（SessionEnd event）觸發 archive

    @Test func testSessionEndEventArchivesBeforeRemoval() {
        let (archiveStore, dir) = makeTmpArchiveStore()
        defer { try? FileManager.default.removeItem(at: dir) }

        let store = SessionStore()
        store.archiveStore = archiveStore

        // 建立 session，做一些工作
        store.apply(event("PreToolUse"), now: t0)
        store.apply(event("Stop"), now: t0.addingTimeInterval(5))

        // SessionEnd → isSessionEnd path → should archive then remove
        let endNow = t0.addingTimeInterval(10)
        store.apply(event("SessionEnd"), now: endNow)

        // session 已被 remove
        #expect((store.session(id: "s1")) == nil, Comment(rawValue: "session should be removed after SessionEnd"))

        // archive 應該有記錄
        let records = archiveStore.records(for: t0)
        #expect((records.count) == (1), Comment(rawValue: "SessionEnd should trigger archive"))

        let record = records.first!
        #expect((record.sessionId) == ("s1"))
        #expect(abs((record.endedAt.timeIntervalSince1970) - (endNow.timeIntervalSince1970)) <= 1, Comment(rawValue: "endedAt should equal the SessionEnd event timestamp"))
    }

    // MARK: Test 3
    // stale working session 被 prune 時觸發 archive

    @Test func testStaleWorkingSessionPruneArchives() {
        let (archiveStore, dir) = makeTmpArchiveStore()
        defer { try? FileManager.default.removeItem(at: dir) }

        let store = SessionStore(staleActiveAfter: 300)
        store.archiveStore = archiveStore

        store.apply(event("PreToolUse"), now: t0)

        // 超過 staleActiveAfter 閾值
        let pruneNow = t0.addingTimeInterval(300)
        store.prune(now: pruneNow)

        #expect((store.session(id: "s1")) == nil, Comment(rawValue: "stale working session should be removed"))

        let records = archiveStore.records(for: t0)
        #expect((records.count) == (1), Comment(rawValue: "stale working session removed by prune should be archived"))
        #expect((records.first?.sessionId) == ("s1"))
        #expect(abs((records.first!.endedAt.timeIntervalSince1970) - (pruneNow.timeIntervalSince1970)) <= 1)
    }

    // MARK: Test 4
    // archiveStore == nil 時 prune/apply 無 crash（backward compatible）

    @Test func testNilArchiveStoreDoesNotCrashOnPrune() {
        let store = SessionStore(doneToIdleAfter: 10, removeIdleAfter: 20)
        // archiveStore 預設 nil，唔設定

        store.apply(event("PreToolUse"), now: t0)
        store.apply(event("Stop"), now: t0.addingTimeInterval(1))

        // prune → done → idle
        store.prune(now: t0.addingTimeInterval(15))
        // prune → remove idle（no archiveStore → should not crash）
        store.prune(now: t0.addingTimeInterval(45))

        #expect((store.session(id: "s1")) == nil, Comment(rawValue: "session should be removed even without archiveStore"))
    }

    @Test func testNilArchiveStoreDoesNotCrashOnSessionEnd() {
        let store = SessionStore()
        // archiveStore == nil

        store.apply(event("PreToolUse"), now: t0)
        store.apply(event("SessionEnd"), now: t0.addingTimeInterval(5))

        #expect((store.session(id: "s1")) == nil, Comment(rawValue: "session removed without archiveStore should not crash"))
    }

    // MARK: Test 5
    // 現有測試 regression check（SessionStore 基本行為唔受影響）

    @Test func testExistingBehaviourUnaffected_applyCreatesSession() {
        let store = SessionStore()
        let s = store.apply(event("PreToolUse"), now: t0)
        #expect((s?.state) == (.working))
        #expect((store.sessions.count) == (1))
    }

    @Test func testExistingBehaviourUnaffected_pruneRemovesLongIdle() {
        let store = SessionStore(doneToIdleAfter: 30, removeIdleAfter: 60)
        store.apply(event("Stop"), now: t0)
        store.prune(now: t0.addingTimeInterval(40))   // done → idle
        store.prune(now: t0.addingTimeInterval(110))  // idle → remove
        #expect((store.session(id: "s1")) == nil)
    }

    // MARK: Test 6
    // 同一 session 跨 prune cycle 唔會 archive 兩次

    @Test func testSameSessionNotArchivedTwiceAcrossPruneCycles() {
        let (archiveStore, dir) = makeTmpArchiveStore()
        defer { try? FileManager.default.removeItem(at: dir) }

        let store = SessionStore(doneToIdleAfter: 10, removeIdleAfter: 20)
        store.archiveStore = archiveStore

        store.apply(event("PreToolUse"), now: t0)
        store.apply(event("Stop"), now: t0.addingTimeInterval(1))

        // first prune cycle: done → idle
        store.prune(now: t0.addingTimeInterval(15))
        // second prune cycle: idle → remove (archive here)
        store.prune(now: t0.addingTimeInterval(40))
        // third prune cycle: session already gone, no-op
        store.prune(now: t0.addingTimeInterval(60))

        let records = archiveStore.records(for: t0)
        #expect((records.count) == (1), Comment(rawValue: "same session must not be archived more than once across prune cycles"))
    }

    // MARK: - createdAt correctness

    // createdAt 應係 session 首次 apply 時嘅 `now`，唔隨後續 event 更新

    @Test func testCreatedAtIsSetOnFirstApplyAndNotUpdatedBySubsequentEvents() {
        let store = SessionStore()

        let firstEventTime = t0
        let laterEventTime = t0.addingTimeInterval(50)

        store.apply(event("PreToolUse"), now: firstEventTime)
        store.apply(event("Stop"), now: laterEventTime)

        let session = store.session(id: "s1")
        #expect((session) != nil)
        #expect(abs((session!.createdAt.timeIntervalSince1970) - (firstEventTime.timeIntervalSince1970)) <= 0.001, Comment(rawValue: "createdAt must equal the first event time and not be overwritten by later events"))
        #expect(abs((session!.updatedAt.timeIntervalSince1970) - (laterEventTime.timeIntervalSince1970)) <= 0.001, Comment(rawValue: "updatedAt should reflect the most recent event"))
    }
}
