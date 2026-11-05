import Foundation
import CryptoKit
import AgentPetCore

/// All blocking disk-image and signature work runs off the main actor.
/// Neither this type nor the installer script removes preferences, Application Support or Keychain items.
enum UpdateInstaller {
    struct Result: Sendable {
        let status: Int32
        let output: String
    }
    struct Plan: Sendable {
        let directory: URL
        let script: URL
        let staged: URL
        let target: URL
        let backup: URL
        let candidate: URL
        let needsAuthorization: Bool
    }

    @discardableResult
    static func run(_ executable: String, _ arguments: [String]) throws -> Result {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return Result(status: process.terminationStatus, output: String(decoding: data, as: UTF8.self))
    }

    static func verifyDownload(_ url: URL, asset: GitHubRelease.Asset) throws {
        guard let expected = asset.sha256,
              let size = try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber,
              size.int64Value == asset.size else { throw AppUpdateError.message("The download is incomplete. Please download it again.") }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hash = SHA256()
        while let data = try handle.read(upToCount: 1024 * 1024), !data.isEmpty {
            try Task.checkCancellation()
            hash.update(data: data)
        }
        guard hash.finalize().map({ String(format: "%02x", $0) }).joined() == expected else {
            throw AppUpdateError.message("The download checksum does not match. Installation was stopped.")
        }
    }

    static func info(_ app: URL) throws -> [String: Any] {
        let data = try Data(contentsOf: app.appendingPathComponent("Contents/Info.plist"))
        guard let result = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
            throw AppUpdateError.message("This is not a valid LuMate application.")
        }
        return result
    }

    static func validateInstalled(_ app: URL) throws {
        let path = app.standardizedFileURL
        guard path.pathExtension == "app", path == path.resolvingSymlinksInPath(),
              !path.path.hasPrefix("/Volumes/"), !path.path.contains("/AppTranslocation/"),
              let metadata = try? info(app),
              metadata["CFBundleIdentifier"] as? String == LocalConfiguration.releaseIdentifier,
              metadata["AgentPetDevelopmentBuild"] as? Bool != true else {
            throw AppUpdateError.message("Install the release app in Applications and launch it there before updating. Development builds cannot be replaced by a release.")
        }
    }

    static func prepare(dmg: URL, asset: GitHubRelease.Asset, version: String, installed: URL, script: URL, workspaceRoot: URL? = nil) throws -> Plan {
        try validateInstalled(installed)
        try verifyDownload(dmg, asset: asset) // Recheck even if the DMG was changed after download.
        let fm = FileManager.default
        let root = workspaceRoot ?? fm.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("local.agentpet/Updates", isDirectory: true)
        let directory = root.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fm.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        var prepared = false
        defer { if !prepared { try? fm.removeItem(at: directory) } }
        let helper = directory.appendingPathComponent("UpdateInstaller.sh")
        try fm.copyItem(at: script, to: helper)
        let mount = directory.appendingPathComponent("mount", isDirectory: true)
        try fm.createDirectory(at: mount, withIntermediateDirectories: true)
        let attached = try run("/usr/bin/hdiutil", ["attach", "-readonly", "-nobrowse", "-noautoopen", "-mountpoint", mount.path, dmg.path])
        guard attached.status == 0 else { throw AppUpdateError.message("The disk image could not be opened. The current app was not changed.") }
        defer {
            if (try? run("/usr/bin/hdiutil", ["detach", mount.path]).status) != 0 {
                _ = try? run("/usr/bin/hdiutil", ["detach", "-force", mount.path])
            }
        }
        let source = mount.appendingPathComponent("LuMate.app")
        let staged = directory.appendingPathComponent("LuMate.app")
        guard source == source.resolvingSymlinksInPath(),
              try run("/usr/bin/ditto", [source.path, staged.path]).status == 0 else {
            throw AppUpdateError.message("The update application could not be prepared. The current app was not changed.")
        }
        try validateApplication(staged, version: version, installed: installed)
        let parent = installed.deletingLastPathComponent()
        let id = UUID().uuidString
        let plan = Plan(directory: directory, script: helper, staged: staged, target: installed,
                    backup: parent.appendingPathComponent(".LuMate-backup-\(id).app"),
                    candidate: parent.appendingPathComponent(".LuMate-install-\(id).app"),
                    needsAuthorization: !fm.isWritableFile(atPath: parent.path) || !fm.isWritableFile(atPath: installed.path))
        prepared = true
        return plan
    }

    static func validateApplication(_ app: URL, version: String, installed: URL) throws {
        let metadata = try info(app)
        guard metadata["CFBundleIdentifier"] as? String == LocalConfiguration.releaseIdentifier,
              metadata["CFBundleExecutable"] as? String == "agentpet",
              metadata["AgentPetDevelopmentBuild"] as? Bool != true,
              let actual = metadata["CFBundleShortVersionString"] as? String,
              ReleaseVersion(actual) == ReleaseVersion(version), ReleaseVersion(actual) != nil,
              let previous = try info(installed)["CFBundleShortVersionString"] as? String,
              let current = ReleaseVersion(previous), let next = ReleaseVersion(actual), next > current else {
            throw AppUpdateError.message("The update identity or version is invalid. Installation was stopped.")
        }
        if let minimum = metadata["LSMinimumSystemVersion"] as? String {
            guard let parsed = ReleaseVersion(minimum) else { throw AppUpdateError.message("This update requires a newer version of macOS.") }
            let os = OperatingSystemVersion(majorVersion: parsed.parts[0], minorVersion: parsed.parts[1], patchVersion: parsed.parts[2])
            guard ProcessInfo.processInfo.isOperatingSystemAtLeast(os) else { throw AppUpdateError.message("This update requires a newer version of macOS.") }
        }
        #if arch(arm64)
        let architecture = "arm64"
        #else
        let architecture = "x86_64"
        #endif
        guard try run("/usr/bin/lipo", [app.appendingPathComponent("Contents/MacOS/agentpet").path, "-verify_arch", architecture]).status == 0,
              try run("/usr/bin/codesign", ["--verify", "--deep", "--strict", app.path]).status == 0 else {
            throw AppUpdateError.message("The update signature or Mac architecture is invalid. Installation was stopped.")
        }
        // Ad-hoc builds have no Team ID. A Developer ID installation must keep its signing team.
        if let team = try signingTeam(installed), try signingTeam(app) != team {
            throw AppUpdateError.message("The update signing team does not match the installed app.")
        }
    }

    static func signingTeam(_ app: URL) throws -> String? {
        let result = try run("/usr/bin/codesign", ["-dv", "--verbose=4", app.path])
        return result.output.split(separator: "\n").first { $0.hasPrefix("TeamIdentifier=") }
            .map { String($0.dropFirst("TeamIdentifier=".count)) }.flatMap { $0 == "not set" ? nil : $0 }
    }

    static func shellQuote(_ text: String) -> String { "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'" }
    static func execute(_ plan: Plan, mode: String) throws {
        let args = [plan.script.path, mode, plan.staged.path, plan.target.path, plan.backup.path, plan.candidate.path]
        let result: Result
        if plan.needsAuthorization {
            let command = (["/bin/sh"] + args).map(shellQuote).joined(separator: " ")
            let escaped = command.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
            result = try run("/usr/bin/osascript", ["-e", "do shell script \"\(escaped)\" with administrator privileges"])
        } else {
            result = try run("/bin/sh", args)
        }
        try? result.output.write(to: plan.directory.appendingPathComponent("installation.log"), atomically: true, encoding: .utf8)
        guard result.status == 0 else { throw AppUpdateError.message("Installation failed or authorization was cancelled. Your data and the previous application were kept.") }
    }

    static func launchRestarter(_ plan: Plan, processID: Int32) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [plan.script.path, "relaunch", plan.target.path, String(processID), plan.backup.path, plan.directory.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
    }

    static var bundledScript: URL? {
        Bundle.main.url(forResource: "UpdateInstaller", withExtension: "sh")
            ?? Bundle.module.url(forResource: "UpdateInstaller", withExtension: "sh")
    }
}
