import Testing
import Foundation
@testable import AgentPetCore

@Suite(.serialized)
final class HookInstallerTests {
    private let cmd = "\"/Applications/AgentPet.app/Contents/MacOS/agentpet\" hook"

    private func groups(_ settings: [String: Any], _ event: String) -> [[String: Any]] {
        (settings["hooks"] as? [String: Any])?[event] as? [[String: Any]] ?? []
    }

    @Test func testInstallIntoEmptyAddsAllEvents() {
        let result = HookInstaller.install(into: [:], command: cmd)
        #expect(HookInstaller.isInstalled(in: result))
        for event in HookInstaller.events {
            #expect((groups(result, event).count) == (1), Comment(rawValue: "event \(event)"))
        }
    }

    @Test func testInstallIsIdempotent() {
        let once = HookInstaller.install(into: [:], command: cmd)
        let twice = HookInstaller.install(into: once, command: cmd)
        for event in HookInstaller.events {
            #expect((groups(twice, event).count) == (1), Comment(rawValue: "no duplicate on \(event)"))
        }
    }

    @Test func testInstallPreservesForeignHooks() {
        let existing: [String: Any] = [
            "hooks": ["Stop": [["hooks": [["type": "command", "command": "echo done"]]]]],
        ]
        let result = HookInstaller.install(into: existing, command: cmd)
        #expect((groups(result, "Stop").count) == (2), Comment(rawValue: "foreign + ours"))
    }

    @Test func testUninstallRemovesOursKeepsForeign() {
        let existing: [String: Any] = [
            "hooks": ["Stop": [["hooks": [["type": "command", "command": "echo done"]]]]],
        ]
        let installed = HookInstaller.install(into: existing, command: cmd)
        let removed = HookInstaller.uninstall(from: installed)
        #expect(!(HookInstaller.isInstalled(in: removed)))
        #expect((groups(removed, "Stop").count) == (1), Comment(rawValue: "foreign hook survives"))
        // Events that were only ours are dropped entirely.
        #expect(groups(removed, "SessionStart").isEmpty)
    }

    @Test func testUninstallFromCleanIsNoop() {
        let removed = HookInstaller.uninstall(from: [:])
        #expect((removed["hooks"]) == nil)
    }

    @Test func testDiskRoundTrip() throws {
        let path = NSTemporaryDirectory() + "settings-\(UUID().uuidString).json"
        defer { try? FileManager.default.removeItem(atPath: path) }
        try HookInstaller.installToDisk(command: cmd, path: path)
        #expect(HookInstaller.isInstalledOnDisk(path: path))
        try HookInstaller.uninstallFromDisk(path: path)
        #expect(!(HookInstaller.isInstalledOnDisk(path: path)))
    }

    // MARK: - Unreadable settings must never be rewritten

    private func tempFile(_ contents: String) throws -> String {
        let path = NSTemporaryDirectory() + "settings-\(UUID().uuidString).json"
        try Data(contents.utf8).write(to: URL(fileURLWithPath: path))
        return path
    }

    @Test func testInstallRefusesToRewriteUnparseableSettings() throws {
        let path = try tempFile("{ not json")
        defer { try? FileManager.default.removeItem(atPath: path) }
        #expect { try HookInstaller.installToDisk(command: cmd, path: path) } throws: { error in
            #expect((error as? HookInstallerError) == (.unreadableSettings(path: path)))
            return true
        }
        #expect((try String(contentsOfFile: path, encoding: .utf8)) == ("{ not json"), Comment(rawValue: "file untouched"))
    }

    @Test func testUninstallRefusesToRewriteUnparseableSettings() throws {
        let path = try tempFile("{ not json")
        defer { try? FileManager.default.removeItem(atPath: path) }
        #expect(throws: (any Error).self) { try HookInstaller.uninstallFromDisk(path: path) }
        #expect((try String(contentsOfFile: path, encoding: .utf8)) == ("{ not json"), Comment(rawValue: "file untouched"))
    }

    @Test func testInstallRefusesNonObjectRoot() throws {
        let path = try tempFile("[1, 2, 3]")
        defer { try? FileManager.default.removeItem(atPath: path) }
        #expect(throws: (any Error).self) { try HookInstaller.installToDisk(command: cmd, path: path) }
    }

    @Test func testEmptyFileIsTreatedAsEmptySettings() throws {
        let path = try tempFile("")
        defer { try? FileManager.default.removeItem(atPath: path) }
        try HookInstaller.installToDisk(command: cmd, path: path)
        #expect(HookInstaller.isInstalledOnDisk(path: path))
    }

    @Test func testIsInstalledOnDiskIsFalseForUnreadableSettings() throws {
        let path = try tempFile("{ not json")
        defer { try? FileManager.default.removeItem(atPath: path) }
        #expect(!(HookInstaller.isInstalledOnDisk(path: path)))
    }
}
