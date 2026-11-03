import Testing
import Foundation
@testable import AgentPetCore

/// Token usage from jcode session files (`~/.jcode/sessions/<id>.json`).
/// Shapes copied from real sessions (2026-10-04).
@Suite(.serialized)
final class JcodeUsageTests {

    private func session(_ usages: [String]) -> Data {
        let messages = usages.map { u in
            #"{"role":"user","content":[{"type":"text","text":"say \"token_usage\": hi"}]},"#
                + #"{"role":"assistant","content":[],"token_usage":\#(u)}"#
        }
        return Data(#"{"id":"session_x_1","messages":[\#(messages.joined(separator: ","))],"compaction":null}"#.utf8)
    }

    /// Anthropic: input_tokens is already uncached, prompt = input + both cache fields.
    @Test func testClaudeUsageCountsUncachedInputPlusOutput() {
        let data = session([
            #"{"prompt_tokens":88127,"input_tokens":482,"output_tokens":705,"cache_read_input_tokens":86688,"cache_creation_input_tokens":957}"#,
        ])
        #expect((JcodeUsage.totalTokens(sessionData: data)) == (482 + 705))
    }

    /// OpenAI: input_tokens includes the cached part, so it must not be added as is.
    @Test func testOpenAIUsageSubtractsCachedPrompt() {
        let data = session([
            #"{"prompt_tokens":109406,"input_tokens":109406,"output_tokens":275,"cache_read_input_tokens":108032,"cache_creation_input_tokens":0}"#,
        ])
        #expect((JcodeUsage.totalTokens(sessionData: data)) == (109406 - 108032 + 275))
    }

    /// Sums every message, ignores the key quoted inside text, tolerates a null
    /// cache field and a usage without prompt_tokens.
    @Test func testSumsAllMessagesAndSkipsQuotedKey() {
        let data = session([
            #"{"prompt_tokens":100,"input_tokens":10,"output_tokens":5,"cache_read_input_tokens":90,"cache_creation_input_tokens":0}"#,
            #"{"prompt_tokens":50,"input_tokens":50,"output_tokens":1,"cache_read_input_tokens":null,"cache_creation_input_tokens":null}"#,
            #"{"input_tokens":7,"output_tokens":3}"#,
        ])
        #expect((JcodeUsage.totalTokens(sessionData: data)) == ((10 + 5) + (50 + 1) + (7 + 3)))
    }

    @Test func testPrettyPrintedKeyIsFound() {
        let data = Data(#"{"messages":[{"token_usage": {"input_tokens": 4, "output_tokens": 2}}]}"#.utf8)
        #expect((JcodeUsage.totalTokens(sessionData: data)) == (6))
    }

    @Test func testNotASessionGivesZero() {
        #expect((JcodeUsage.totalTokens(sessionData: Data("not json".utf8))) == (0))
        #expect((JcodeUsage.totalTokens(sessionData: Data(#"{"token_usage":{"input_tokens":3"#.utf8))) == (0))
    }

    @Test func testSessionPathRejectsTraversal() {
        #expect((JcodeUsage.sessionPath(sessionId: "session_x_1", home: "/h")) == ("/h/.jcode/sessions/session_x_1.json"))
        #expect((JcodeUsage.sessionPath(sessionId: "../auth", home: "/h")) == nil)
        #expect((JcodeUsage.sessionPath(sessionId: "a/b", home: "/h")) == nil)
        #expect((JcodeUsage.sessionPath(sessionId: "", home: "/h")) == nil)
        #expect((JcodeUsage.journalPath(snapshotPath: "/h/.jcode/sessions/session_x_1.json")) == ("/h/.jcode/sessions/session_x_1.journal.jsonl"))
    }

    /// jcode appends new messages to `<id>.journal.jsonl` and only rewrites the
    /// snapshot every 512 KB, so the turn's tokens are usually in the journal.
    @Test func testTotalAddsJournalToSnapshot() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let snapshot = dir.appendingPathComponent("session_x_1.json")
        try session([#"{"input_tokens":10,"output_tokens":5}"#]).write(to: snapshot)
        #expect((JcodeUsage.totalTokens(snapshotPath: snapshot.path)) == (15))   // no journal yet

        let journal = dir.appendingPathComponent("session_x_1.journal.jsonl")
        let lines = [
            #"{"meta":{"title":"t"},"append_messages":[{"role":"assistant","content":[],"token_usage":{"input_tokens":3,"output_tokens":2}}]}"#,
            #"{"meta":{"title":"t"},"append_messages":[{"role":"user","content":[]}]}"#,
        ]
        try Data((lines.joined(separator: "\n") + "\n").utf8).write(to: journal)
        #expect((JcodeUsage.totalTokens(snapshotPath: snapshot.path)) == (15 + 5))
        #expect((JcodeUsage.totalTokens(snapshotPath: dir.appendingPathComponent("missing.json").path)) == (0))
    }

    // MARK: tracker

    @Test func testTurnFeedsOnlyItsOwnTokens() {
        var t = JcodeUsageTracker()
        t.baseline(sessionId: "s", total: 4_500_000)   // turn_start of a long session
        #expect((t.delta(sessionId: "s", total: 4_512_000)) == (12_000))
        t.baseline(sessionId: "s", total: 4_512_000)   // next turn_start: already tracked
        #expect((t.delta(sessionId: "s", total: 4_520_000)) == (8_000))
    }

    /// AgentPet started mid-turn: the first turn_end only sets the baseline.
    @Test func testFirstSightingFeedsNothing() {
        var t = JcodeUsageTracker()
        #expect((t.delta(sessionId: "s", total: 4_500_000)) == (0))
        #expect((t.delta(sessionId: "s", total: 4_501_000)) == (1_000))
    }

    /// Compaction drops old messages: no negative feed, new baseline instead.
    @Test func testShrinkingTotalMovesBaseline() {
        var t = JcodeUsageTracker()
        t.baseline(sessionId: "s", total: 900)
        #expect((t.delta(sessionId: "s", total: 300)) == (0))
        #expect((t.delta(sessionId: "s", total: 350)) == (50))
    }

    /// Sessions that never send session_end must not pile up forever.
    @Test func testTrackerKeepsOnlyRecentSessions() {
        var t = JcodeUsageTracker()
        let cap = JcodeUsageTracker.maxSessions
        for i in 0..<(cap + 50) { t.baseline(sessionId: "s\(i)", total: 10) }
        #expect((t.count) == (cap))
        #expect(!(t.isTracking("s0")))
        #expect(t.isTracking("s\(cap + 49)"))
        // A dropped session just re-baselines: nothing is fed.
        #expect((t.delta(sessionId: "s0", total: 999)) == (0))
    }

    @Test func testBaselineDoesNotOverwriteAndForgetResets() {
        var t = JcodeUsageTracker()
        t.baseline(sessionId: "s", total: 100)
        t.baseline(sessionId: "s", total: 999)
        #expect((t.delta(sessionId: "s", total: 150)) == (50))
        t.forget(sessionId: "s")
        #expect(!(t.isTracking("s")))
        #expect((t.delta(sessionId: "s", total: 5_000)) == (0))
    }
}
