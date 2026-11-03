import Testing
import Foundation
@testable import AgentPetCore

@Suite(.serialized)
final class ClaudeHookPayloadTests {
    private let now = Date(timeIntervalSince1970: 100)

    private func payload(_ json: String) -> ClaudeHookPayload? {
        ClaudeHookPayload.decode(from: Data(json.utf8))
    }

    @Test func testDecodesSessionStart() {
        let event = payload(#"{"session_id":"abc","cwd":"/Users/x/proj","hook_event_name":"SessionStart"}"#)?
            .makeEvent(now: now)
        #expect((event?.sessionId) == ("abc"))
        #expect((event?.project) == ("/Users/x/proj"))
        #expect((event?.eventName) == ("SessionStart"))
        #expect((event?.agentKind) == (.claude))
    }

    @Test func testDecodesNotificationWithMessage() {
        let p = payload(#"{"session_id":"s","cwd":"/p","hook_event_name":"Notification","message":"needs permission"}"#)
        let event = p?.makeEvent(now: now)
        #expect((event?.message) == ("needs permission"))
        #expect((StateMapper.state(for: .claude, eventName: event!.eventName)) == (.waiting))
    }

    @Test func testIgnoresUnknownFields() {
        // Real Claude payloads carry extra keys (transcript_path, stop_hook_active, ...).
        let event = payload(#"{"session_id":"s","hook_event_name":"Stop","transcript_path":"/t","stop_hook_active":false}"#)?
            .makeEvent(now: now)
        #expect((event?.eventName) == ("Stop"))
        #expect((event?.project) == nil)
    }

    @Test func testNilWhenMissingEssentialFields() {
        #expect((payload(#"{"cwd":"/p"}"#)?.makeEvent(now: now)) == nil)
        #expect((payload("not json")) == nil)
    }

    // MARK: - model field

    @Test func testDecodesModelDisplayName() {
        let json = #"{"session_id":"s","hook_event_name":"Stop","model":{"id":"claude-sonnet-4-6-20250514","display_name":"Sonnet 4.6"}}"#
        let event = payload(json)?.makeEvent(now: now)
        #expect((event?.model) == ("Sonnet 4.6"))
    }

    @Test func testFallsBackToModelIdWhenNoDisplayName() {
        let json = #"{"session_id":"s","hook_event_name":"Stop","model":{"id":"gpt-5.1"}}"#
        let event = payload(json)?.makeEvent(now: now)
        #expect((event?.model) == ("gpt-5.1"))
    }

    @Test func testDecodesBareStringModel() {
        let json = #"{"session_id":"s","hook_event_name":"Stop","model":"some-model"}"#
        let event = payload(json)?.makeEvent(now: now)
        #expect((event?.model) == ("some-model"))
    }

    @Test func testNilModelWhenAbsent() {
        let json = #"{"session_id":"s","hook_event_name":"Stop"}"#
        let event = payload(json)?.makeEvent(now: now)
        #expect((event?.model) == nil)
    }

    @Test func testMalformedModelDoesNotBreakDecode() {
        // model is a number, not an object/string — must not fail the whole payload.
        let json = #"{"session_id":"s","hook_event_name":"Stop","model":123}"#
        let event = payload(json)?.makeEvent(now: now)
        #expect((event?.eventName) == ("Stop"), Comment(rawValue: "payload must still decode"))
        #expect((event?.model) == nil)
    }

    // MARK: - Other agents routed through ClaudeHookPayload (claudeNested style)

    @Test func testCodexPreToolUseActivityMessage() {
        let json = #"{"session_id":"cx1","cwd":"/proj","hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"npm test"}}"#
        let event = payload(json)?.makeEvent(now: now, kind: .codex)
        #expect((event?.agentKind) == (.codex))
        #expect(ActivityTheme.chef.running.contains(event?.message ?? ""), Comment(rawValue: "got \(event?.message ?? "nil")"))
    }

    @Test func testGeminiBeforeToolActivityMessage() {
        let json = #"{"session_id":"gm1","cwd":"/proj","hook_event_name":"BeforeTool","tool_name":"run_shell_command","tool_input":{"command":"ls"}}"#
        let event = payload(json)?.makeEvent(now: now, kind: .gemini)
        #expect((event?.agentKind) == (.gemini))
        #expect(ActivityTheme.chef.running.contains(event?.message ?? ""), Comment(rawValue: "got \(event?.message ?? "nil")"))
    }

    // MARK: - approval gating (PreToolUse + Bash)

    @Test func testPreToolUseBashPopulatesApprovalFields() {
        let json = #"{"session_id":"s","cwd":"/proj","hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"npm test"}}"#
        let event = payload(json)?.makeEvent(now: now, gatedTools: ["Bash"])
        #expect((event?.approvalRequestId) != nil, Comment(rawValue: "must generate a request id for a gated tool"))
        #expect((event?.toolName) == ("Bash"))
        #expect((event?.toolSummary) == ("npm test"))
    }

    @Test func testPreToolUseBashTruncatesSummaryTo80Characters() {
        let longCommand = String(repeating: "a", count: 200)
        let json = #"{"session_id":"s","cwd":"/proj","hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"\#(longCommand)"}}"#
        let event = payload(json)?.makeEvent(now: now, gatedTools: ["Bash"])
        #expect((event?.toolSummary?.count) == (80), Comment(rawValue: "summary must be truncated to 80 chars"))
    }

    @Test func testPreToolUseBashWithNoCommandFallsBackToToolName() {
        let json = #"{"session_id":"s","cwd":"/proj","hook_event_name":"PreToolUse","tool_name":"Bash"}"#
        let event = payload(json)?.makeEvent(now: now, gatedTools: ["Bash"])
        #expect((event?.toolSummary) == ("Bash"), Comment(rawValue: "no command in tool_input -> summary falls back to tool name"))
    }

    @Test func testPreToolUseNonGatedToolLeavesApprovalFieldsNil() {
        let json = #"{"session_id":"s","cwd":"/proj","hook_event_name":"PreToolUse","tool_name":"Read","tool_input":{"file_path":"/x"}}"#
        let event = payload(json)?.makeEvent(now: now, gatedTools: ["Bash"])
        #expect((event?.approvalRequestId) == nil, Comment(rawValue: "Read is not in the gated tool whitelist"))
        #expect((event?.toolName) == nil)
        #expect((event?.toolSummary) == nil)
    }

    @Test func testEmptyGatedToolsDisablesApprovalEvenForBash() {
        let json = #"{"session_id":"s","cwd":"/proj","hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"npm test"}}"#
        let event = payload(json)?.makeEvent(now: now, gatedTools: [])
        #expect((event?.approvalRequestId) == nil, Comment(rawValue: "empty whitelist means the gate is off"))
        #expect((event?.toolName) == nil)
        #expect((event?.toolSummary) == nil)
    }

    @Test func testNonPreToolUseEventLeavesApprovalFieldsNilEvenForBash() {
        let json = #"{"session_id":"s","cwd":"/proj","hook_event_name":"Stop","tool_name":"Bash","tool_input":{"command":"npm test"}}"#
        let event = payload(json)?.makeEvent(now: now, gatedTools: ["Bash"])
        #expect((event?.approvalRequestId) == nil, Comment(rawValue: "only PreToolUse should ever trigger gating"))
        #expect((event?.toolName) == nil)
        #expect((event?.toolSummary) == nil)
    }

    @Test func testPreToolUseBashForNonClaudeKindLeavesApprovalFieldsNil() {
        let json = #"{"session_id":"s","cwd":"/proj","hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"npm test"}}"#

        let codexEvent = payload(json)?.makeEvent(now: now, kind: .codex, gatedTools: ["Bash"])
        #expect((codexEvent?.approvalRequestId) == nil, Comment(rawValue: "approval gating is a Claude-only contract"))
        #expect((codexEvent?.toolName) == nil)
        #expect((codexEvent?.toolSummary) == nil)

        let droidEvent = payload(json)?.makeEvent(now: now, kind: .droid, gatedTools: ["Bash"])
        #expect((droidEvent?.approvalRequestId) == nil, Comment(rawValue: "approval gating is a Claude-only contract"))
        #expect((droidEvent?.toolName) == nil)
        #expect((droidEvent?.toolSummary) == nil)
    }
}

// MARK: - ApprovalGateConfig (opt-in whitelist file)

@Suite(.serialized)
final class ApprovalGateConfigTests {
    @Test func testMissingConfigMeansGateOff() {
        let missing = NSTemporaryDirectory() + "agentpet-missing-\(UUID().uuidString).json"
        #expect((ApprovalGateConfig.gatedTools(path: missing)) == ([]))
    }

    @Test func testValidConfigEnablesListedTools() throws {
        let path = NSTemporaryDirectory() + "agentpet-gate-\(UUID().uuidString).json"
        try #"{"tools":["Bash","Write"]}"#.write(toFile: path, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(atPath: path) }
        #expect((ApprovalGateConfig.gatedTools(path: path)) == (["Bash", "Write"]))
    }

    @Test func testMalformedConfigMeansGateOff() throws {
        let path = NSTemporaryDirectory() + "agentpet-gate-\(UUID().uuidString).json"
        try "not json".write(toFile: path, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(atPath: path) }
        #expect((ApprovalGateConfig.gatedTools(path: path)) == ([]))
    }

    @Test func testSetEnabledWritesFileAndIsEnabledReadsIt() {
        let path = NSTemporaryDirectory() + "agentpet-gate-\(UUID().uuidString).json"
        defer { try? FileManager.default.removeItem(atPath: path) }
        ApprovalGateConfig.setEnabled(true, path: path)
        #expect(ApprovalGateConfig.isEnabled(path: path))
        #expect((ApprovalGateConfig.gatedTools(path: path)) == (["Bash"]))
    }

    @Test func testSetEnabledFalseRemovesFile() {
        let path = NSTemporaryDirectory() + "agentpet-gate-\(UUID().uuidString).json"
        ApprovalGateConfig.setEnabled(true, path: path)
        #expect(FileManager.default.fileExists(atPath: path))
        ApprovalGateConfig.setEnabled(false, path: path)
        #expect(!(FileManager.default.fileExists(atPath: path)))
        #expect(!(ApprovalGateConfig.isEnabled(path: path)))
    }
}
