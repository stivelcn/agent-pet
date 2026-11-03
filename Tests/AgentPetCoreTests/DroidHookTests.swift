import Testing
import Foundation
@testable import AgentPetCore

/// Hook integration tests for the Factory Droid CLI (`droid`). Droid uses the
/// same nested `~/.factory/hooks.json` shape and snake_case stdin payload as
/// Claude Code, so it reuses the claudeNested installer and ClaudeHookPayload.
@Suite(.serialized)
final class DroidHookTests {

    private func tmp(_ name: String) -> String {
        NSTemporaryDirectory() + "agentpet-test-\(UUID().uuidString)/\(name)"
    }

    @Test func testDroidSpec() {
        let spec = AgentHooks.spec(for: .droid)!
        #expect((spec.style) == (.claudeNested))
        #expect(spec.settingsPath.hasSuffix("/.factory/hooks.json"))
        // Notification is Droid's permission/approval (human-in-the-loop) signal.
        #expect(spec.events.contains("Notification"))
        #expect(spec.events.contains("PreToolUse"))
        #expect(spec.events.contains("Stop"))
        #expect(spec.events.contains("SessionEnd"))
    }

    @Test func testDroidInstallShapeAndRoundTrip() throws {
        let spec = AgentHooks.spec(for: .droid)!
        let path = tmp("hooks.json")
        let cmd = "\"/x/agentpet\" hook --agent droid"
        try HookInstaller.installToDisk(command: cmd, path: path, events: spec.events, style: .claudeNested)
        let json = try HookInstaller.readSettings(path: path)
        // Nested Claude shape: hooks -> Notification -> [{ hooks: [{type, command}] }].
        let groups = (json["hooks"] as? [String: Any])?["Notification"] as? [[String: Any]]
        let inner = groups?.first?["hooks"] as? [[String: Any]]
        #expect((inner?.first?["type"] as? String) == ("command"))
        #expect((inner?.first?["command"] as? String ?? "").contains("agentpet"))
        #expect(HookInstaller.isInstalledOnDisk(path: path, events: spec.events, style: .claudeNested))
        try HookInstaller.uninstallFromDisk(path: path, events: spec.events, style: .claudeNested)
        #expect(!(HookInstaller.isInstalledOnDisk(path: path, events: spec.events, style: .claudeNested)))
        try? FileManager.default.removeItem(atPath: (path as NSString).deletingLastPathComponent)
    }

    @Test func testDroidInstallPreservesForeignHooks() throws {
        let spec = AgentHooks.spec(for: .droid)!
        let path = tmp("hooks.json")
        // A user's own Notification hook must survive install + uninstall.
        let foreign: [String: Any] = ["hooks": ["Notification": [["hooks": [["type": "command", "command": "say hi"]]]]]]
        try HookInstaller.writeSettings(foreign, path: path)
        try HookInstaller.installToDisk(command: "\"/x/agentpet\" hook --agent droid", path: path, events: spec.events, style: .claudeNested)
        try HookInstaller.uninstallFromDisk(path: path, events: spec.events, style: .claudeNested)
        let notif = ((try HookInstaller.readSettings(path: path))["hooks"] as? [String: Any])?["Notification"] as? [[String: Any]]
        let cmds = notif?.compactMap { ($0["hooks"] as? [[String: Any]])?.first?["command"] as? String } ?? []
        #expect((cmds) == (["say hi"]), Comment(rawValue: "foreign Notification hook preserved after our round-trip"))
        try? FileManager.default.removeItem(atPath: (path as NSString).deletingLastPathComponent)
    }

    @Test func testDroidStates() {
        #expect((StateMapper.state(for: .droid, eventName: "SessionStart")) == (.registered))
        #expect((StateMapper.state(for: .droid, eventName: "UserPromptSubmit")) == (.working))
        #expect((StateMapper.state(for: .droid, eventName: "PreToolUse")) == (.working))
        #expect((StateMapper.state(for: .droid, eventName: "Notification")) == (.waiting))
        #expect((StateMapper.state(for: .droid, eventName: "Stop")) == (.done))
        // SubagentStop must not flip a finished session back to working.
        #expect((StateMapper.state(for: .droid, eventName: "SubagentStop")) == nil)
    }

    @Test func testDroidSessionEnd() {
        #expect(StateMapper.isSessionEnd(for: .droid, eventName: "SessionEnd"))
        #expect(!(StateMapper.isSessionEnd(for: .droid, eventName: "Stop")))
    }

    @Test func testDroidPayloadDecodesWithKind() {
        let data = Data(#"{"session_id":"d1","cwd":"/proj","hook_event_name":"Notification","message":"Droid needs your permission to run a command","permission_mode":"off"}"#.utf8)
        let event = HookPayload.event(forAgent: .droid, stdin: data, now: Date())
        #expect((event?.agentKind) == (.droid))
        #expect((event?.eventName) == ("Notification"))
        #expect((event?.sessionId) == ("d1"))
        #expect((event?.project) == ("/proj"))
    }

    @Test func testDroidInCatalog() {
        let droid = AgentCatalog.all.first { $0.kind == .droid }
        #expect((droid) != nil)
        #expect(droid?.isSupported ?? false)
        #expect((droid?.displayName) == ("Factory Droid"))
    }
}
