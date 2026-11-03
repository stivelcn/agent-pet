import Testing
import Foundation
@testable import AgentPetCore

/// Hook integration tests for GitHub Copilot CLI and Kiro CLI. Verifies the
/// on-disk config shape matches each tool's documented format, that install is
/// idempotent + reversible, and that events map to the right states.
@Suite(.serialized)
final class KiroCopilotHookTests {

    private func tmp(_ name: String) -> String {
        NSTemporaryDirectory() + "agentpet-test-\(UUID().uuidString)/\(name)"
    }

    // MARK: - GitHub Copilot (~/.copilot/hooks/*.json, cursor-flat shape)

    @Test func testCopilotSpec() {
        let spec = AgentHooks.spec(for: .copilot)!
        #expect((spec.style) == (.cursorFlat))
        #expect(spec.settingsPath.hasSuffix("/.copilot/hooks/agentpet.json"))
        // PreToolUse must NOT be registered: its command hook is fail-closed and
        // a crash there would block the user's tools.
        #expect(!(spec.events.contains("PreToolUse")))
        #expect(spec.events.contains("PostToolUse"))
        #expect(spec.events.contains("Stop"))
    }

    @Test func testCopilotInstallShapeAndRoundTrip() throws {
        let spec = AgentHooks.spec(for: .copilot)!
        let path = tmp("agentpet.json")
        let cmd = "\"/x/agentpet\" hook --agent copilot"
        try HookInstaller.installToDisk(command: cmd, path: path, events: spec.events, style: .cursorFlat)
        let json = try HookInstaller.readSettings(path: path)
        #expect((json["version"] as? Int) == (1))
        let stop = (json["hooks"] as? [String: Any])?["Stop"] as? [[String: Any]]
        #expect((stop?.first?["type"] as? String) == ("command"))
        #expect((stop?.first?["command"] as? String ?? "").contains("agentpet"))
        #expect(HookInstaller.isInstalledOnDisk(path: path, events: spec.events, style: .cursorFlat))
        try HookInstaller.uninstallFromDisk(path: path, events: spec.events, style: .cursorFlat)
        #expect(!(HookInstaller.isInstalledOnDisk(path: path, events: spec.events, style: .cursorFlat)))
        try? FileManager.default.removeItem(atPath: (path as NSString).deletingLastPathComponent)
    }

    @Test func testCopilotStates() {
        #expect((StateMapper.state(for: .copilot, eventName: "SessionStart")) == (.registered))
        #expect((StateMapper.state(for: .copilot, eventName: "PostToolUse")) == (.working))
        #expect((StateMapper.state(for: .copilot, eventName: "Stop")) == (.done))
    }

    @Test func testCopilotPayloadDecodesWithKind() {
        let data = Data(#"{"session_id":"s1","cwd":"/proj","hook_event_name":"PostToolUse","tool_name":"bash"}"#.utf8)
        let event = HookPayload.event(forAgent: .copilot, stdin: data, now: Date())
        #expect((event?.agentKind) == (.copilot))
        #expect((event?.eventName) == ("PostToolUse"))
        #expect((event?.sessionId) == ("s1"))
    }

    // MARK: - Kiro CLI (~/.kiro/agents/default.json, hooks merged into agent)

    @Test func testKiroSpec() {
        let spec = AgentHooks.spec(for: .kiroCLI)!
        #expect((spec.style) == (.kiroFlat))
        #expect(spec.settingsPath.hasSuffix("/.kiro/agents/default.json"))
        #expect(!(spec.events.contains("preToolUse")))
    }

    @Test func testKiroInstallShapePreservesAgentFields() throws {
        let spec = AgentHooks.spec(for: .kiroCLI)!
        let path = tmp("default.json")
        // Pre-existing agent file with real fields that must survive.
        try HookInstaller.writeSettings(["name": "default", "prompt": "be helpful"], path: path)
        let cmd = "\"/x/agentpet\" hook --agent kiroCLI"
        try HookInstaller.installToDisk(command: cmd, path: path, events: spec.events, style: .kiroFlat)
        let json = try HookInstaller.readSettings(path: path)
        #expect((json["name"] as? String) == ("default"), Comment(rawValue: "agent name preserved"))
        #expect((json["prompt"] as? String) == ("be helpful"), Comment(rawValue: "agent prompt preserved"))
        #expect((json["version"]) == nil, Comment(rawValue: "Kiro agent file has no version field"))
        let stop = (json["hooks"] as? [String: Any])?["stop"] as? [[String: Any]]
        #expect((stop?.count) == (1))
        #expect((stop?.first?["type"]) == nil, Comment(rawValue: "Kiro hook items are plain {command}"))
        #expect((stop?.first?["show_output"]) == nil)
        #expect((stop?.first?["command"] as? String ?? "").contains("agentpet"))
        #expect(HookInstaller.isInstalledOnDisk(path: path, events: spec.events, style: .kiroFlat))
        try HookInstaller.uninstallFromDisk(path: path, events: spec.events, style: .kiroFlat)
        #expect(!(HookInstaller.isInstalledOnDisk(path: path, events: spec.events, style: .kiroFlat)))
        #expect(((try HookInstaller.readSettings(path: path))["name"] as? String) == ("default"), Comment(rawValue: "agent survives uninstall"))
        try? FileManager.default.removeItem(atPath: (path as NSString).deletingLastPathComponent)
    }

    @Test func testKiroSeedsNameWhenCreatingFresh() throws {
        let spec = AgentHooks.spec(for: .kiroCLI)!
        let path = tmp("default.json")
        try HookInstaller.installToDisk(command: "\"/x/agentpet\" hook --agent kiroCLI", path: path, events: spec.events, style: .kiroFlat)
        #expect(((try HookInstaller.readSettings(path: path))["name"] as? String) == ("default"), Comment(rawValue: "a fresh Kiro agent file gets a name so it is a valid agent"))
        try? FileManager.default.removeItem(atPath: (path as NSString).deletingLastPathComponent)
    }

    @Test func testKiroStates() {
        #expect((StateMapper.state(for: .kiroCLI, eventName: "agentSpawn")) == (.registered))
        #expect((StateMapper.state(for: .kiroCLI, eventName: "postToolUse")) == (.working))
        #expect((StateMapper.state(for: .kiroCLI, eventName: "stop")) == (.done))
        // Tolerate PascalCase too, in case Kiro reports event names that way.
        #expect((StateMapper.state(for: .kiroCLI, eventName: "Stop")) == (.done))
    }
}
