import Testing
import Foundation
@testable import AgentPetCore

/// jcode integration: observer hooks in ~/.jcode/config.toml `[hooks]`, event
/// delivered through JCODE_HOOK_* env vars (docs/HOOKS.md upstream).
@Suite(.serialized)
final class JcodeHookTests {
    private let cmd = "\"/x/agentpet\" hook --agent jcode"
    private var events: [String] { AgentHooks.spec(for: .jcode)!.events }

    // MARK: payload

    @Test func testEnvPayloadBuildsEvent() {
        let e = JcodeHookPayload.event(env: [
            "JCODE_HOOK_EVENT": "post_tool", "JCODE_HOOK_SESSION_ID": "session_x_1",
            "JCODE_HOOK_CWD": "/proj", "JCODE_HOOK_TOOL_NAME": "bash",
        ], now: Date())
        #expect((e?.agentKind) == (.jcode))
        #expect((e?.eventName) == ("post_tool"))
        #expect((e?.sessionId) == ("session_x_1"))
        #expect((e?.project) == ("/proj"))
        #expect((e?.message) != nil, Comment(rawValue: "tool activity feeds the bubble"))
    }

    @Test func testMissingSessionOrEventIsIgnored() {
        #expect((JcodeHookPayload.event(env: ["JCODE_HOOK_EVENT": "turn_end"], now: Date())) == nil)
        #expect((JcodeHookPayload.event(env: ["JCODE_HOOK_SESSION_ID": "s"], now: Date())) == nil)
        #expect((JcodeHookPayload.event(env: [:], now: Date())) == nil)
    }

    @Test func testTurnEndingOnQuestionIsWaiting() {
        let env = ["JCODE_HOOK_EVENT": "turn_end", "JCODE_HOOK_SESSION_ID": "s",
                   "JCODE_HOOK_STATUS": "ok",
                   "JCODE_HOOK_LAST_ASSISTANT_TEXT": "I found two options. Which one should I use?"]
        #expect((JcodeHookPayload.event(env: env, now: Date())?.eventName) == ("waiting"))
    }

    @Test func testTurnEndingWithSummaryIsDone() {
        let env = ["JCODE_HOOK_EVENT": "turn_end", "JCODE_HOOK_SESSION_ID": "s",
                   "JCODE_HOOK_STATUS": "ok", "JCODE_HOOK_LAST_ASSISTANT_TEXT": "Fixed the bug and tests pass."]
        let e = JcodeHookPayload.event(env: env, now: Date())
        #expect((e?.eventName) == ("turn_end"))
        #expect((StateMapper.state(for: .jcode, eventName: e!.eventName)) == (.done))
    }

    // MARK: state mapping

    @Test func testStateMapping() {
        #expect((StateMapper.state(for: .jcode, eventName: "session_start")) == (.registered))
        #expect((StateMapper.state(for: .jcode, eventName: "turn_start")) == (.working))
        #expect((StateMapper.state(for: .jcode, eventName: "post_tool")) == (.working))
        #expect((StateMapper.state(for: .jcode, eventName: "turn_end")) == (.done))
        #expect((StateMapper.state(for: .jcode, eventName: "pre_tool")) == nil)
        #expect(StateMapper.isSessionEnd(for: .jcode, eventName: "session_end"))
        #expect(!(StateMapper.isSessionEnd(for: .jcode, eventName: "turn_end")))
    }

    @Test func testSpecUsesObserversOnly() {
        let spec = AgentHooks.spec(for: .jcode)!
        #expect((spec.style) == (.jcodeToml))
        #expect(spec.settingsPath.hasSuffix("/.jcode/config.toml"))
        #expect(!(spec.events.contains("pre_tool")), Comment(rawValue: "pre_tool is a blocking gate"))
    }

    @Test func testInCatalog() {
        #expect((AgentCatalog.all.first { $0.kind == .jcode }?.isSupported) == (true))
    }

    // MARK: TOML config

    private let sample = """
    # user comment
    [display]
    debug_socket = false

    [hooks]
    pre_tool_timeout_ms = 5000

    [ambient]
    enabled = false
    """

    @Test func testInstallAddsKeysInsideHooksTableOnly() throws {
        let out = try JcodeHookConfig.install(in: sample, command: cmd, events: events)
        let lines = out.components(separatedBy: "\n")
        let hooks = lines.firstIndex(of: "[hooks]")!, ambient = lines.firstIndex(of: "[ambient]")!
        for event in events {
            let i = try #require(lines.firstIndex(of: "\(event) = '\(cmd)'"))
            #expect(i > hooks && i < ambient, Comment(rawValue: "\(event) must sit in [hooks]"))
        }
        // Everything else is untouched.
        #expect((JcodeHookConfig.uninstall(in: out, events: events)) == (sample))
        #expect(JcodeHookConfig.isInstalled(in: out, events: events))
        #expect(!(JcodeHookConfig.isInstalled(in: sample, events: events)))
    }

    @Test func testInstallIsIdempotent() throws {
        let once = try JcodeHookConfig.install(in: sample, command: cmd, events: events)
        #expect((try JcodeHookConfig.install(in: once, command: cmd, events: events)) == (once))
        // A moved binary rewrites our lines in place instead of duplicating them.
        let moved = try JcodeHookConfig.install(in: once, command: "\"/y/agentpet\" hook --agent jcode", events: events)
        #expect((moved.components(separatedBy: "\n").count) == (once.components(separatedBy: "\n").count))
        #expect(moved.contains("/y/agentpet") && !moved.contains("/x/agentpet"))
    }

    @Test func testInstallCreatesHooksTableWhenMissing() throws {
        let out = try JcodeHookConfig.install(in: "[display]\nx = 1\n", command: cmd, events: ["turn_end"])
        #expect(out.hasPrefix("[display]\nx = 1\n\n[hooks]\nturn_end = '"))
        #expect(try JcodeHookConfig.install(in: "", command: cmd, events: ["turn_end"]).hasPrefix("[hooks]\n"))
    }

    /// A second `[hooks]` table is invalid TOML and makes jcode drop the whole
    /// config, so every header spelling must be found, not appended again.
    @Test func testHeaderVariantsAreFoundNotDuplicated() throws {
        for header in ["[hooks] # observers", "[ hooks ]", "\t[hooks]\t", "[hooks]\r"] {
            let src = "\(header)\npre_tool = \"x\"\n"
            let out = try JcodeHookConfig.install(in: src, command: cmd, events: ["turn_end"])
            let headers = out.components(separatedBy: "\n").filter(JcodeHookConfig.isHooksHeader)
            #expect((headers.count) == (1), Comment(rawValue: "header \(header.debugDescription)"))
            #expect(JcodeHookConfig.isInstalled(in: out, events: ["turn_end"]))
            #expect((JcodeHookConfig.uninstall(in: out, events: ["turn_end"])) == (src))
        }
        #expect(!(JcodeHookConfig.isHooksHeader("[[hooks]]")))
        #expect(!(JcodeHookConfig.isHooksHeader("# [hooks]")))
        #expect(!(JcodeHookConfig.isHooksHeader("[hooks.extra]")))
    }

    @Test func testForeignHookIsNeverOverwritten() {
        let foreign = sample.replacingOccurrences(of: "pre_tool_timeout_ms = 5000",
                                                  with: "pre_tool_timeout_ms = 5000\nturn_end = \"~/bin/notify\"")
        #expect { try JcodeHookConfig.install(in: foreign, command: cmd, events: events) } throws: { error in
            #expect((error as? JcodeHookConfigError) == (.conflictingHook(event: "turn_end", path: "config.toml")))
            return true
        }
        #expect((JcodeHookConfig.uninstall(in: foreign, events: events)) == (foreign))
    }

    @Test func testCommentedKeysAndSimilarNamesAreIgnored() throws {
        let toml = "[hooks]\n# turn_end = \"old\"\nturn_end_extra = 1\n"
        let out = try JcodeHookConfig.install(in: toml, command: cmd, events: ["turn_end"])
        #expect(out.contains("# turn_end = \"old\"\nturn_end_extra = 1"))
        #expect(out.contains("turn_end = '\(cmd)'"))
    }

    @Test func testCommandWithApostropheUsesBasicString() {
        // A single quote can't live in a TOML literal string, so it falls back
        // to a basic string with the inner double quotes escaped.
        #expect((JcodeHookConfig.tomlString(#""/a b's/agentpet" hook"#)) == (#""\"/a b's/agentpet\" hook""#))
        #expect((JcodeHookConfig.tomlString(#""/x/agentpet" hook"#)) == (#"'"/x/agentpet" hook'"#))
    }

    @Test func testDiskRoundTrip() throws {
        let dir = NSTemporaryDirectory() + "agentpet-test-\(UUID().uuidString)"
        let path = dir + "/config.toml"
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: dir) }
        try Data(sample.utf8).write(to: URL(fileURLWithPath: path))
        try HookInstaller.installToDisk(command: cmd, path: path, events: events, style: .jcodeToml)
        #expect(HookInstaller.isInstalledOnDisk(path: path, events: events, style: .jcodeToml))
        try HookInstaller.uninstallFromDisk(path: path, events: events, style: .jcodeToml)
        #expect(!(HookInstaller.isInstalledOnDisk(path: path, events: events, style: .jcodeToml)))
        #expect((try String(contentsOfFile: path, encoding: .utf8)) == (sample))
    }
}
