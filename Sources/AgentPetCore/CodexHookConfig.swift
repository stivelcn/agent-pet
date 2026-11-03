import Foundation

/// Ensures Codex's hook feature is enabled in `~/.codex/config.toml`. Codex only
/// reads our `~/.codex/hooks.json` when hooks are on. They are on by default on
/// recent Codex, but older versions need `[features] hooks = true` (the key
/// `codex_hooks` is a deprecated alias). We set it conservatively so the
/// integration works regardless of version, without touching any other config.
///
/// The string transform is pure (and tested); `enableHooksOnDisk` wraps it with
/// atomic file IO. It never adds a duplicate key and never edits unrelated keys.
public enum CodexHookConfig {
    public static func homeDirectory() -> String {
        if let path = ProcessInfo.processInfo.environment["CODEX_HOME"], path.hasPrefix("/") { return path }
        return NSHomeDirectory() + "/.codex"
    }

    public static func defaultConfigPath() -> String {
        homeDirectory() + "/config.toml"
    }

    /// Only the root [features] table controls hooks; similarly named project/model keys do not.
    static func featureLines(_ lines: [String]) -> [Int] {
        var inFeatures = false
        var result: [Int] = []
        for (index, raw) in lines.enumerated() {
            let line = raw.split(separator: "#", maxSplits: 1).first.map(String.init)?.trimmingCharacters(in: .whitespaces) ?? ""
            if line.hasPrefix("[") { inFeatures = line == "[features]"; continue }
            if inFeatures { result.append(index) }
        }
        return result
    }

    static func alreadyEnabled(_ toml: String) -> Bool {
        let lines = toml.components(separatedBy: "\n")
        return featureLines(lines).contains { index in
            let part = lines[index].split(separator: "#", maxSplits: 1).first.map(String.init) ?? ""
            let pair = part.components(separatedBy: "=").map { $0.trimmingCharacters(in: .whitespaces) }
            return pair == ["hooks", "true"]
        }
    }

    public static func enableHooks(in toml: String) -> String? {
        if alreadyEnabled(toml) { return nil }
        var lines = toml.components(separatedBy: "\n")
        for index in featureLines(lines) {
            let line = lines[index]
            let key = line.components(separatedBy: "=").first?.trimmingCharacters(in: .whitespaces)
            if key == "hooks" {
                let comment = line.firstIndex(of: "#").map { " " + line[$0...] } ?? ""
                lines[index] = "hooks = true" + comment
                return lines.joined(separator: "\n")
            }
        }
        if let index = lines.firstIndex(where: {
            $0.components(separatedBy: "#")[0].trimmingCharacters(in: .whitespaces) == "[features]"
        }) {
            lines.insert("hooks = true", at: index + 1)
            return lines.joined(separator: "\n")
        }
        var result = toml
        if !result.isEmpty && !result.hasSuffix("\n") { result += "\n" }
        return result + "\n[features]\nhooks = true\n"
    }

    /// Reads the config (empty if missing), enables hooks if needed, and writes
    /// it back atomically. No-op if already enabled.
    public static func enableHooksOnDisk(path: String = defaultConfigPath()) throws {
        let existing = (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""
        guard let updated = enableHooks(in: existing) else { return }
        let dir = (path as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        try Data(updated.utf8).write(to: URL(fileURLWithPath: path), options: .atomic)
    }
}
