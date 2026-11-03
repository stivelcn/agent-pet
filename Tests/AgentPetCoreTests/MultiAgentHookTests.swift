import Testing
import Foundation
@testable import AgentPetCore

@Suite(.serialized)
final class MultiAgentHookTests {
    private let cmd = "\"/Applications/AgentPet.app/Contents/MacOS/agentpet\" hook --agent cursor"

    // MARK: - Cursor flat shape

    @Test func testCursorInstallShape() {
        let events = AgentHooks.spec(for: .cursor)!.events
        let result = HookInstaller.installFlat(into: [:], command: cmd, events: events, style: .cursorFlat)
        #expect((result["version"] as? Int) == (1))
        #expect(HookInstaller.isInstalledFlat(in: result, events: events))
        let hooks = result["hooks"] as? [String: Any]
        let stop = hooks?["stop"] as? [[String: Any]]
        #expect((stop?.count) == (1))
        #expect((stop?.first?["type"] as? String) == ("command"))
        #expect((stop?.first?["command"] as? String ?? "").contains("agentpet"))
    }

    @Test func testCursorIdempotentAndForeignPreserved() {
        let events = AgentHooks.spec(for: .cursor)!.events
        let existing: [String: Any] = ["hooks": ["stop": [["command": "echo hi"]]]]
        let once = HookInstaller.installFlat(into: existing, command: cmd, events: events, style: .cursorFlat)
        let twice = HookInstaller.installFlat(into: once, command: cmd, events: events, style: .cursorFlat)
        let stop = (twice["hooks"] as? [String: Any])?["stop"] as? [[String: Any]]
        #expect((stop?.count) == (2), Comment(rawValue: "foreign + ours, no duplicate"))
        let removed = HookInstaller.uninstallFlat(from: twice, events: events)
        let stopAfter = (removed["hooks"] as? [String: Any])?["stop"] as? [[String: Any]]
        #expect((stopAfter?.count) == (1), Comment(rawValue: "foreign kept"))
        #expect(!(HookInstaller.isInstalledFlat(in: removed, events: events)))
    }

    // MARK: - Windsurf flat shape

    @Test func testWindsurfInstallShape() {
        let events = AgentHooks.spec(for: .windsurf)!.events
        let cmd = "\"/x/agentpet\" hook --agent windsurf"
        let result = HookInstaller.installFlat(into: [:], command: cmd, events: events, style: .windsurfFlat)
        #expect((result["version"]) == nil, Comment(rawValue: "Windsurf has no version field"))
        let resp = (result["hooks"] as? [String: Any])?["post_cascade_response"] as? [[String: Any]]
        #expect((resp?.first?["command"] as? String) == (cmd))
        #expect((resp?.first?["show_output"] as? Bool) == (false))
        #expect(HookInstaller.isInstalledFlat(in: result, events: events))
    }

    // MARK: - Antigravity named-group shape

    @Test func testAntigravityInstallShape() {
        let events = AgentHooks.spec(for: .antigravity)!.events
        let cmd = "\"/x/agentpet\" hook --agent antigravity"
        let result = HookInstaller.installAntigravity(into: [:], command: cmd, events: events)
        #expect((result["hooks"]) == nil, Comment(rawValue: "Antigravity nests under a named group, not \"hooks\""))
        let group = result[HookInstaller.antigravityGroup] as? [String: Any]
        // Stop / PreInvocation: a plain list of handlers directly under the event.
        let stop = group?["Stop"] as? [[String: Any]]
        #expect((stop?.count) == (1))
        #expect((stop?.first?["type"] as? String) == ("command"))
        #expect((stop?.first?["command"] as? String) == (cmd))
        #expect((stop?.first?["hooks"]) == nil, Comment(rawValue: "Stop handlers are not wrapped in a hooks array"))
        // PreToolUse / PostToolUse: matcher + nested hooks array.
        let pre = group?["PreToolUse"] as? [[String: Any]]
        #expect((pre?.first?["matcher"] as? String) == ("*"))
        let preInner = pre?.first?["hooks"] as? [[String: Any]]
        #expect((preInner?.first?["command"] as? String) == (cmd))
        #expect(HookInstaller.isInstalledAntigravity(in: result, events: events))
    }

    @Test func testAntigravityIdempotentAndForeignPreserved() {
        let events = AgentHooks.spec(for: .antigravity)!.events
        let cmd = "\"/x/agentpet\" hook --agent antigravity"
        // A foreign hook group plus a foreign entry under one of our events.
        let existing: [String: Any] = [
            "my-linter": ["PostToolUse": [["hooks": [["type": "command", "command": "lint.sh"]]]]],
            HookInstaller.antigravityGroup: ["Stop": [["hooks": [["type": "command", "command": "echo hi"]]]]],
        ]
        let once = HookInstaller.installAntigravity(into: existing, command: cmd, events: events)
        let twice = HookInstaller.installAntigravity(into: once, command: cmd, events: events)
        let group = twice[HookInstaller.antigravityGroup] as? [String: Any]
        let stop = group?["Stop"] as? [[String: Any]]
        #expect((stop?.count) == (2), Comment(rawValue: "foreign Stop entry + ours, no duplicate"))
        #expect((twice["my-linter"]) != nil, Comment(rawValue: "foreign hook group untouched"))
        let removed = HookInstaller.uninstallAntigravity(from: twice, events: events)
        let stopAfter = (removed[HookInstaller.antigravityGroup] as? [String: Any])?["Stop"] as? [[String: Any]]
        #expect((stopAfter?.count) == (1), Comment(rawValue: "foreign Stop entry kept"))
        #expect((removed["my-linter"]) != nil, Comment(rawValue: "foreign hook group still kept"))
        #expect(!(HookInstaller.isInstalledAntigravity(in: removed, events: events)))
    }

    @Test func testAntigravityStateMapping() {
        #expect((StateMapper.state(for: .antigravity, eventName: "PreInvocation")) == (.working))
        #expect((StateMapper.state(for: .antigravity, eventName: "PreToolUse")) == (.working))
        #expect((StateMapper.state(for: .antigravity, eventName: "Stop")) == (.done))
        #expect((StateMapper.state(for: .antigravity, eventName: "Unknown")) == nil)
    }

    @Test func testAntigravityPayloadDecode() {
        // Antigravity sends camelCase stdin with no event name; the state is
        // inferred from the discriminator fields (toolCall -> working).
        let json = #"{"conversationId":"ag1","workspacePaths":["/proj"],"stepIdx":0,"toolCall":{"name":"run_command"}}"#
        let ev = HookPayload.event(forAgent: .antigravity, stdin: Data(json.utf8), now: Date())
        #expect((ev?.sessionId) == ("ag1"))
        #expect((ev?.eventName) == ("working"))
        #expect((ev?.project) == ("/proj"))
        #expect((ev?.agentKind) == (.antigravity))
    }

    // MARK: - opencode plugin

    @Test func testOpencodeBinaryPathExtraction() {
        #expect((HookInstaller.binaryPath(fromCommand: "\"/Applications/AgentPet.app/Contents/MacOS/agentpet\" hook --agent opencode")) == ("/Applications/AgentPet.app/Contents/MacOS/agentpet"))
    }

    @Test func testOpencodePluginContent() {
        let js = HookInstaller.opencodePlugin(binary: "/x/agentpet")
        #expect(js.contains("session.idle"))
        #expect(js.contains("session.created"))
        #expect(js.contains("--agent"))
        #expect(js.contains("opencode"))
        #expect(HookInstaller.isOurs(js.replacingOccurrences(of: "\n", with: " ")))
    }

    // MARK: - Payload parsing

    @Test func testCursorPayloadDecode() {
        let json = #"{"conversation_id":"c1","hook_event_name":"stop","workspace_roots":["/proj"],"model":"x"}"#
        let ev = HookPayload.event(forAgent: .cursor, stdin: Data(json.utf8), now: Date())
        #expect((ev?.sessionId) == ("c1"))
        #expect((ev?.eventName) == ("stop"))
        #expect((ev?.project) == ("/proj"))
        #expect((ev?.agentKind) == (.cursor))
    }

    @Test func testCursorPayloadDecodesModel() {
        let json = #"{"conversation_id":"c1","hook_event_name":"stop","model":{"display_name":"Sonnet 4.6"}}"#
        let e = HookPayload.event(forAgent: .cursor, stdin: Data(json.utf8), now: Date())
        #expect((e?.model) == ("Sonnet 4.6"))
    }

    @Test func testCursorPayloadModelAbsentIsNil() {
        let json = #"{"conversation_id":"c1","hook_event_name":"stop"}"#
        let e = HookPayload.event(forAgent: .cursor, stdin: Data(json.utf8), now: Date())
        #expect((e?.model) == nil)
    }

    @Test func testWindsurfPayloadDecodesModel() {
        let json = #"{"trajectory_id":"t1","agent_action_name":"post_cascade_response","model":{"display_name":"GPT-5.1"}}"#
        let e = HookPayload.event(forAgent: .windsurf, stdin: Data(json.utf8), now: Date())
        #expect((e?.model) == ("GPT-5.1"))
    }

    @Test func testCursorPreToolUseReadFileActivityMessage() {
        let json = #"{"conversation_id":"c10","hook_event_name":"preToolUse","tool_name":"read_file","tool_input":{"file_path":"README.md"},"workspace_roots":["/proj"]}"#
        let ev = HookPayload.event(forAgent: .cursor, stdin: Data(json.utf8), now: Date())
        #expect((ev?.message) == ("Reading the docs…"))
    }

    @Test func testCursorPreToolUseRunCommandActivityMessage() {
        let json = #"{"conversation_id":"c11","hook_event_name":"preToolUse","tool_name":"run_terminal_cmd","tool_input":{"command":"npm test"},"workspace_roots":["/proj"]}"#
        let ev = HookPayload.event(forAgent: .cursor, stdin: Data(json.utf8), now: Date())
        #expect(ActivityTheme.chef.running.contains(ev?.message ?? ""), Comment(rawValue: "got \(ev?.message ?? "nil")"))
    }

    @Test func testCursorStopHasNoActivityMessage() {
        let json = #"{"conversation_id":"c12","hook_event_name":"stop","workspace_roots":["/proj"]}"#
        let ev = HookPayload.event(forAgent: .cursor, stdin: Data(json.utf8), now: Date())
        #expect((ev?.message) == nil)
    }

    @Test func testWindsurfPayloadDecode() {
        let json = #"{"trajectory_id":"t1","agent_action_name":"post_cascade_response","model_name":"x"}"#
        let ev = HookPayload.event(forAgent: .windsurf, stdin: Data(json.utf8), now: Date())
        #expect((ev?.sessionId) == ("t1"))
        #expect((ev?.eventName) == ("post_cascade_response"))
        #expect((ev?.agentKind) == (.windsurf))
    }

    // MARK: - State mapping

    @Test func testCursorStateMapping() {
        #expect((StateMapper.state(for: .cursor, eventName: "sessionStart")) == (.registered))
        #expect((StateMapper.state(for: .cursor, eventName: "beforeSubmitPrompt")) == (.working))
        #expect((StateMapper.state(for: .cursor, eventName: "stop")) == (.done))
    }

    @Test func testWindsurfStateMapping() {
        #expect((StateMapper.state(for: .windsurf, eventName: "pre_user_prompt")) == (.working))
        #expect((StateMapper.state(for: .windsurf, eventName: "post_cascade_response")) == (.done))
    }

    @Test func testOpencodeNormalisedStatePassThrough() {
        // The plugin sends normalised state names directly.
        #expect((StateMapper.state(for: .opencode, eventName: "done")) == (.done))
        #expect((StateMapper.state(for: .opencode, eventName: "working")) == (.working))
        #expect((StateMapper.state(for: .opencode, eventName: "session.idle")) == (.done))
    }

    // MARK: - Session end clears the session

    @Test func testSessionEndRemovesSession() {
        let store = SessionStore()
        let now = Date()
        let start = AgentEvent(sessionId: "s1", agentKind: .claude, eventName: "SessionStart",
                               project: "/p", message: nil, timestamp: now)
        #expect((store.apply(start, now: now)) != nil)
        #expect((store.sessions.count) == (1))
        let end = AgentEvent(sessionId: "s1", agentKind: .claude, eventName: "SessionEnd",
                             project: "/p", message: nil, timestamp: now)
        #expect((store.apply(end, now: now)) == nil, Comment(rawValue: "SessionEnd maps to no state"))
        #expect((store.sessions.count) == (0), Comment(rawValue: "session cleared on quit"))
    }

    @Test func testIsSessionEnd() {
        #expect(StateMapper.isSessionEnd(for: .claude, eventName: "SessionEnd"))
        #expect(StateMapper.isSessionEnd(for: .gemini, eventName: "SessionEnd"))
        #expect(StateMapper.isSessionEnd(for: .cursor, eventName: "sessionEnd"))
        #expect(!(StateMapper.isSessionEnd(for: .claude, eventName: "Stop")))
        #expect(!(StateMapper.isSessionEnd(for: .codex, eventName: "Stop")))
    }

    // MARK: - Disk round-trip for each new style

    @Test func testDiskRoundTripAllStyles() throws {
        let tmp = NSTemporaryDirectory() + "agentpet-test-\(UUID().uuidString)/"
        defer { try? FileManager.default.removeItem(atPath: tmp) }
        let cases: [(AgentKind, String)] = [(.cursor, "cursor.json"), (.windsurf, "windsurf.json"), (.opencode, "plugin/agentpet.js"), (.antigravity, "config/hooks.json")]
        for (kind, file) in cases {
            let spec = AgentHooks.spec(for: kind)!
            let path = tmp + file
            let command = "\"/Applications/AgentPet.app/Contents/MacOS/agentpet\" hook --agent \(kind.rawValue)"
            #expect(!(HookInstaller.isInstalledOnDisk(path: path, events: spec.events, style: spec.style)), Comment(rawValue: "\(kind) clean"))
            try HookInstaller.installToDisk(command: command, path: path, events: spec.events, style: spec.style)
            #expect(HookInstaller.isInstalledOnDisk(path: path, events: spec.events, style: spec.style), Comment(rawValue: "\(kind) installed"))
            try HookInstaller.uninstallFromDisk(path: path, events: spec.events, style: spec.style)
            #expect(!(HookInstaller.isInstalledOnDisk(path: path, events: spec.events, style: spec.style)), Comment(rawValue: "\(kind) removed"))
        }
    }
}
