import Testing
import Foundation
@testable import AgentPetCore

/// Integration tests for Pi (pi.dev). Pi has no Claude-style command hooks; it
/// loads a TypeScript extension from ~/.pi/agent/extensions/ that reports state
/// through the `agentpet hook` CLI with explicit flags (like the opencode plugin).
@Suite(.serialized)
final class PiHookTests {

    private func tmp(_ name: String) -> String {
        NSTemporaryDirectory() + "agentpet-test-\(UUID().uuidString)/\(name)"
    }

    @Test func testPiSpec() {
        let spec = AgentHooks.spec(for: .pi)!
        #expect((spec.style) == (.piExtension))
        #expect(spec.settingsPath.hasSuffix("/.pi/agent/extensions/agentpet.ts"))
        // The extension hardcodes its own pi.on() handlers, so no events are
        // registered through the generic installer.
        #expect(spec.events.isEmpty)
    }

    @Test func testPiExtensionContent() {
        let ts = HookInstaller.piExtension(binary: "/x/agentpet")
        #expect(ts.contains("pi.on(\"session_start\""))
        #expect(ts.contains("pi.on(\"agent_start\""))
        #expect(ts.contains("pi.on(\"agent_end\""))
        #expect(ts.contains("--agent"))
        #expect(ts.contains("pi"))
        // Must look "ours" so isInstalled detection works.
        #expect(HookInstaller.isOurs(ts.replacingOccurrences(of: "\n", with: " ")))
    }

    @Test func testPiExtensionInstallRoundTrip() throws {
        let spec = AgentHooks.spec(for: .pi)!
        let path = tmp("agentpet.ts")
        let cmd = "\"/x/agentpet\" hook --agent pi"
        try HookInstaller.installToDisk(command: cmd, path: path, events: spec.events, style: .piExtension)
        let source = try String(contentsOfFile: path, encoding: .utf8)
        #expect(source.contains("AGENTPET_BIN"))
        #expect(source.contains("/x/agentpet"))
        #expect(HookInstaller.isInstalledOnDisk(path: path, events: spec.events, style: .piExtension))
        try HookInstaller.uninstallFromDisk(path: path, events: spec.events, style: .piExtension)
        #expect(!(HookInstaller.isInstalledOnDisk(path: path, events: spec.events, style: .piExtension)))
        #expect(!(FileManager.default.fileExists(atPath: path)), Comment(rawValue: "extension file removed on uninstall"))
        try? FileManager.default.removeItem(atPath: (path as NSString).deletingLastPathComponent)
    }

    @Test func testPiNormalisedStatesSentByExtension() {
        // The extension sends normalised AgentState raw values directly.
        #expect((StateMapper.state(for: .pi, eventName: "registered")) == (.registered))
        #expect((StateMapper.state(for: .pi, eventName: "working")) == (.working))
        #expect((StateMapper.state(for: .pi, eventName: "done")) == (.done))
    }

    @Test func testPiNativeEventNamesFallback() {
        #expect((StateMapper.state(for: .pi, eventName: "session_start")) == (.registered))
        #expect((StateMapper.state(for: .pi, eventName: "agent_start")) == (.working))
        #expect((StateMapper.state(for: .pi, eventName: "agent_end")) == (.done))
        #expect((StateMapper.state(for: .pi, eventName: "session_shutdown")) == (.done))
        // Pi has no approval gate, so there is no "waiting" event.
        #expect((StateMapper.state(for: .pi, eventName: "extension_ui_request")) == nil)
    }

    @Test func testPiEventViaExplicitFlags() {
        // The extension uses explicit flags, not stdin, like opencode + the run wrapper.
        let args = HookArguments.parse(["--agent", "pi", "--event", "working", "--session", "pi:/proj", "--project", "/proj"])
        let event = args.makeEvent(now: Date())
        #expect((event?.agentKind) == (.pi))
        #expect((event?.eventName) == ("working"))
        #expect((event?.project) == ("/proj"))
    }

    @Test func testPiInCatalog() {
        let pi = AgentCatalog.all.first { $0.kind == .pi }
        #expect((pi) != nil)
        #expect(pi?.isSupported ?? false)
        #expect((pi?.displayName) == ("Pi"))
    }
}
