import Foundation
import Testing
@testable import AgentPetCore

private final class ConnectionFixture {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("agentpet-connection-tests-" + UUID().uuidString)
    init() throws { try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true) }
    deinit { try? FileManager.default.removeItem(at: root) }
    func path(_ relative: String) -> String { root.appendingPathComponent(relative).path }
    func write(_ relative: String, _ text: String, executable: Bool = false) throws {
        let url = root.appendingPathComponent(relative)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
        if executable { try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path) }
    }
    var installer: AgentConnectionInstaller { AgentConnectionInstaller(binaryPath: path("My App/agentpet"), backupRoot: path("backups")) }
    var spec: AgentHookSpec { AgentHookSpec(kind: .codex, style: .claudeNested, events: ["SessionStart", "Stop"], settingsPath: path("codex/hooks.json")) }
    func detected() -> [AgentKind: String] {
        AgentClientDetector.detect(home: path("home"), path: path("bin"), applicationRoots: [path("Applications")], systemBinaryDirectories: [])
    }
}

@Suite(.serialized)
struct LocalConnectionTests {
    @Test func leftoverConfigurationIsNotAnInstalledClient() throws {
        let f = try ConnectionFixture()
        try f.write("home/.codex/config.toml", "")
        try f.write("home/.claude/settings.json", "{}")
        #expect(f.detected().isEmpty)
    }

    @Test func detectsExecutableFromPathAndUserLocalBin() throws {
        let f = try ConnectionFixture()
        try f.write("bin/codex", "#!/bin/sh\nexit 0\n", executable: true)
        try f.write("home/.local/bin/claude", "#!/bin/sh\nexit 0\n", executable: true)
        #expect(f.detected()[.codex] == f.path("bin/codex"))
        #expect(f.detected()[.claude] == f.path("home/.local/bin/claude"))
    }

    @Test func doesNotDetectNonExecutableFiles() throws {
        let f = try ConnectionFixture()
        try f.write("bin/codex", "not a client")
        #expect(f.detected()[.codex] == nil)
    }

    @Test func detectsChatGPTBundledCodexWithoutConfusingClaudeDesktop() throws {
        let f = try ConnectionFixture()
        let cli = "Applications/ChatGPT.app/Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex"
        try f.write(cli, "#!/bin/sh\nexit 0\n", executable: true)
        try f.write("Applications/Claude.app/Contents/MacOS/Claude", "#!/bin/sh\nexit 0\n", executable: true)
        #expect(f.detected()[.codex] == f.path(cli))
        #expect(f.detected()[.claude] == nil)
    }

    @Test func installsBothFilesAndSecondLaunchDoesNotRewriteOrBackUpAgain() throws {
        let f = try ConnectionFixture()
        let config = f.path("codex/config.toml")
        #expect(try f.installer.connect(f.spec, codexConfigPath: config))
        #expect(f.installer.isConfigured(f.spec, codexConfigPath: config))
        let first = try Data(contentsOf: URL(fileURLWithPath: f.spec.settingsPath))
        let backups = try FileManager.default.contentsOfDirectory(atPath: f.path("backups"))
        #expect(backups.count == 1)
        #expect(try !f.installer.connect(f.spec, codexConfigPath: config))
        #expect(try Data(contentsOf: URL(fileURLWithPath: f.spec.settingsPath)) == first)
        #expect(try FileManager.default.contentsOfDirectory(atPath: f.path("backups")) == backups)
    }

    @Test func backsUpOriginalConfigurationAndPreservesOtherSettings() throws {
        let f = try ConnectionFixture()
        let original = "model = \"example-local-model\"\n\n[features]\nother = true\n"
        try f.write("codex/config.toml", original)
        try f.installer.connect(f.spec, codexConfigPath: f.path("codex/config.toml"))
        let updated = try String(contentsOfFile: f.path("codex/config.toml"), encoding: .utf8)
        #expect(updated.contains("model = \"example-local-model\""))
        #expect(updated.contains("other = true"))
        let backup = try #require(FileManager.default.contentsOfDirectory(atPath: f.path("backups")).first)
        #expect(try String(contentsOfFile: f.path("backups/\(backup)/1-config.toml"), encoding: .utf8) == original)
        let attrs = try FileManager.default.attributesOfItem(atPath: f.path("backups/\(backup)/1-config.toml"))
        #expect((attrs[.posixPermissions] as? NSNumber)?.intValue == 0o600)
    }

    @Test func disconnectKeepsForeignHandlerInMixedGroup() throws {
        let f = try ConnectionFixture()
        let command = f.installer.command(for: .codex)
        let old: [String: Any] = ["theme": "synthetic", "hooks": ["Stop": [["matcher": "*", "hooks": [
            ["type": "command", "command": command], ["type": "command", "command": "echo foreign"]
        ]]]]]
        let data = try JSONSerialization.data(withJSONObject: old)
        try f.write("codex/hooks.json", String(decoding: data, as: UTF8.self))
        #expect(try f.installer.disconnect(f.spec))
        let text = try String(contentsOfFile: f.spec.settingsPath, encoding: .utf8)
        #expect(text.contains("echo foreign"))
        #expect(text.contains("synthetic"))
        #expect(text.contains("matcher"))
        #expect(!text.contains(" hook --agent"))
    }

    @Test func preservesDifferentPetInstallationWithoutOverwritingIt() throws {
        let f = try ConnectionFixture()
        let original = #"{"hooks":{"Stop":[{"hooks":[{"type":"command","command":"/other/agentpet hook --agent codex"}]}]}}"#
        try f.write("codex/hooks.json", original)
        #expect(throws: AgentConnectionError.self) { try f.installer.connect(f.spec) }
        #expect(try String(contentsOfFile: f.spec.settingsPath, encoding: .utf8) == original)
        #expect(!FileManager.default.fileExists(atPath: f.path("backups")))
    }

    @Test func malformedJSONIsNotOverwritten() throws {
        let f = try ConnectionFixture()
        try f.write("codex/hooks.json", "{unfinished")
        #expect(throws: (any Error).self) { try f.installer.connect(f.spec) }
        #expect(try String(contentsOfFile: f.spec.settingsPath, encoding: .utf8) == "{unfinished")
    }

    @Test func failedSecondWriteRollsBackFirstWrite() throws {
        let f = try ConnectionFixture()
        try f.write("codex/hooks.json", "{\"keep\": true}")
        try f.write("not-a-directory", "ordinary file")
        #expect(throws: (any Error).self) {
            try f.installer.connect(f.spec, codexConfigPath: f.path("not-a-directory/config.toml"))
        }
        #expect(try String(contentsOfFile: f.spec.settingsPath, encoding: .utf8) == "{\"keep\": true}")
    }

    @Test func nestedFeatureKeysDoNotEnableRootHookFeature() throws {
        let old = "[projects.example.features]\nhooks = true\n"
        let new = try #require(CodexHookConfig.enableHooks(in: old))
        #expect(new.hasPrefix(old))
        #expect(new.contains("\n[features]\nhooks = true"))
    }

    @Test func hookWordInOtherTablesIsNotRewritten() throws {
        let old = "[other]\nhooks = false\n[features] # features comment\nhooks = false # keep comment\n"
        let new = try #require(CodexHookConfig.enableHooks(in: old))
        #expect(new.contains("[other]\nhooks = false"))
        #expect(new.contains("hooks = true # keep comment"))
        #expect(CodexHookConfig.enableHooks(in: new) == nil)
    }

    @Test func disconnectDoesNotDisableGlobalCodexFeatures() throws {
        let f = try ConnectionFixture()
        let config = f.path("codex/config.toml")
        try f.installer.connect(f.spec, codexConfigPath: config)
        let before = try Data(contentsOf: URL(fileURLWithPath: config))
        try f.installer.disconnect(f.spec)
        #expect(try Data(contentsOf: URL(fileURLWithPath: config)) == before)
        #expect(!f.installer.isConfigured(f.spec, codexConfigPath: config))
    }

    @Test func normalLaunchEnablesConfigurationAndTestsCanDisableIt() {
        #expect(LocalConfiguration.allowsHookConfiguration(development: true, optIn: nil))
        #expect(LocalConfiguration.allowsHookConfiguration(development: false, optIn: nil))
        #expect(!LocalConfiguration.allowsHookConfiguration(development: true, optIn: "0"))
        #expect(LocalConfiguration.displayName.contains("LuMate"))
        #expect(LocalConfiguration.preferencesSuite.hasPrefix("local.agentpet.tests."))
    }

    @Test func luMateUpgradeRequiresExplicitDisconnectBeforeChangingHookPath() throws {
        let f = try ConnectionFixture()
        let old = AgentConnectionInstaller(
            binaryPath: f.path("AgentPet Local Dev.app/Contents/MacOS/agentpet"),
            backupRoot: f.path("backups"))
        let renamed = AgentConnectionInstaller(
            binaryPath: f.path("LuMate Dev.app/Contents/MacOS/agentpet"),
            backupRoot: f.path("backups"))
        try old.connect(f.spec)
        let before = try Data(contentsOf: URL(fileURLWithPath: f.spec.settingsPath))
        #expect(throws: AgentConnectionError.self) { try renamed.connect(f.spec) }
        #expect(try Data(contentsOf: URL(fileURLWithPath: f.spec.settingsPath)) == before)
        try old.disconnect(f.spec)
        try renamed.connect(f.spec)
        #expect(renamed.isConfigured(f.spec))
    }

}
