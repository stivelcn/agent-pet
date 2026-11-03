import Testing
import Foundation
@testable import AgentPetCore

/// Native xAI Grok Build integration. Grok's hook payload uses camelCase keys
/// (`hookEventName`, `sessionId`, `toolName`) with snake_case event VALUES
/// (`pre_tool_use`, `stop`) , different from Claude's snake_case keys +
/// PascalCase values, which is why the Claude-compat path never worked (#51).
@Suite(.serialized)
final class GrokHookTests {

    private func tmp(_ name: String) -> String {
        NSTemporaryDirectory() + "agentpet-test-\(UUID().uuidString)/\(name)"
    }

    // The bug from #51: Grok's payload can't decode as a Claude event, so the CLI
    // must fail OPEN (exit 0). Here we prove the decode returns nil for .claude.
    @Test func testGrokPayloadIsNotAClaudeEvent() {
        let grok = #"{"hookEventName":"stop","sessionId":"abc","cwd":"/tmp"}"#.data(using: .utf8)!
        #expect((HookPayload.event(forAgent: .claude, stdin: grok, now: Date())) == nil)
        #expect((HookPayload.event(forAgent: .cursor, stdin: grok, now: Date())) == nil)
    }

    @Test func testGrokPayloadDecodesAsGrok() {
        let grok = #"{"hookEventName":"pre_tool_use","sessionId":"abc-123","cwd":"/Users/me/proj","toolName":"run_terminal_command","toolInput":{"command":"npm test"}}"#.data(using: .utf8)!
        let e = HookPayload.event(forAgent: .grok, stdin: grok, now: Date())
        #expect((e?.agentKind) == (.grok))
        #expect((e?.eventName) == ("pre_tool_use"))
        #expect((e?.sessionId) == ("abc-123"))
        #expect((e?.project) == ("/Users/me/proj"))
    }

    @Test func testGrokFallsBackToWorkspaceRoot() {
        let grok = #"{"hookEventName":"stop","sessionId":"s1","workspaceRoot":"/ws"}"#.data(using: .utf8)!
        let e = HookPayload.event(forAgent: .grok, stdin: grok, now: Date())
        #expect((e?.project) == ("/ws"))
    }

    @Test func testGrokStateMapping() {
        #expect((StateMapper.state(for: .grok, eventName: "session_start")) == (.registered))
        #expect((StateMapper.state(for: .grok, eventName: "user_prompt_submit")) == (.working))
        #expect((StateMapper.state(for: .grok, eventName: "pre_tool_use")) == (.working))
        #expect((StateMapper.state(for: .grok, eventName: "post_tool_use")) == (.working))
        #expect((StateMapper.state(for: .grok, eventName: "notification")) == (.waiting))
        #expect((StateMapper.state(for: .grok, eventName: "stop")) == (.done))
        #expect((StateMapper.state(for: .grok, eventName: "post_compact")) == nil)
    }

    @Test func testGrokSessionEnd() {
        #expect(StateMapper.isSessionEnd(for: .grok, eventName: "session_end"))
        #expect(!(StateMapper.isSessionEnd(for: .grok, eventName: "stop")))
    }

    @Test func testGrokSpec() {
        let spec = AgentHooks.spec(for: .grok)!
        #expect((spec.style) == (.claudeNested))
        #expect(spec.settingsPath.hasSuffix("/.grok/hooks/agentpet.json"))
        // PreToolUse is deliberately omitted (its deny gate is risky).
        #expect(!(spec.events.contains("PreToolUse")))
        #expect(spec.events.contains("Stop"))
        #expect(spec.events.contains("SessionEnd"))
    }

    @Test func testGrokInstallRoundTrip() throws {
        let spec = AgentHooks.spec(for: .grok)!
        let path = tmp("agentpet.json")
        let cmd = "\"/x/agentpet\" hook --agent grok"
        try HookInstaller.installToDisk(command: cmd, path: path, events: spec.events, style: .claudeNested)
        #expect(HookInstaller.isInstalledOnDisk(path: path, events: spec.events, style: .claudeNested))
        let json = try String(contentsOfFile: path, encoding: .utf8)
        #expect(json.contains("--agent grok"))
        try HookInstaller.uninstallFromDisk(path: path, events: spec.events, style: .claudeNested)
        #expect(!(HookInstaller.isInstalledOnDisk(path: path, events: spec.events, style: .claudeNested)))
        try? FileManager.default.removeItem(atPath: (path as NSString).deletingLastPathComponent)
    }

    @Test func testGrokInCatalog() {
        let grok = AgentCatalog.all.first { $0.kind == .grok }
        #expect((grok) != nil)
        #expect(grok?.isSupported ?? false)
        #expect((grok?.displayName) == ("Grok Build"))
    }
}
