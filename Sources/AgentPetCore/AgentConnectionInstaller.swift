import Foundation

public enum AgentConnectionError: LocalizedError {
    case conflict(String)
    case invalid(String)
    public var errorDescription: String? {
        switch self {
        case .conflict(let path): return "检测到其他桌宠或自定义连接，已保留原配置，请先处理冲突：\(path)"
        case .invalid(let path): return "配置格式不正确或无法读取，未覆盖原文件：\(path)"
        }
    }
}

/// Plans changes before writing, keeps private recoverable backups, and rolls back partial failures.
/// Does not alter trust records, credentials, model selection, or approval settings.
public struct AgentConnectionInstaller {
    public let binaryPath: String
    public let backupRoot: String
    public init(binaryPath: String, backupRoot: String) {
        self.binaryPath = binaryPath
        self.backupRoot = backupRoot
    }

    public func command(for kind: AgentKind) -> String {
        let escaped = binaryPath.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "$", with: "\\$")
            .replacingOccurrences(of: "`", with: "\\`")
        return "\"\(escaped)\" hook --agent \(kind.rawValue)"
    }

    public func isConfigured(_ spec: AgentHookSpec, codexConfigPath: String? = nil) -> Bool {
        guard let changes = try? plan(spec, removing: false, codexConfigPath: codexConfigPath) else { return false }
        return changes.isEmpty
    }

    @discardableResult
    public func connect(_ spec: AgentHookSpec, codexConfigPath: String? = nil) throws -> Bool {
        try commit(plan(spec, removing: false, codexConfigPath: codexConfigPath))
    }

    @discardableResult
    public func disconnect(_ spec: AgentHookSpec) throws -> Bool {
        try commit(plan(spec, removing: true, codexConfigPath: nil))
    }

    private struct Change {
        let path: String
        let before: Data?
        let after: Data?
        let permissions: Int
    }

    private func read(_ path: String) throws -> Data? {
        guard FileManager.default.fileExists(atPath: path) else { return nil }
        return try Data(contentsOf: URL(fileURLWithPath: path))
    }

    private func change(_ path: String, _ before: Data?, _ after: Data?) -> Change? {
        guard before != after else { return nil }
        let attrs = try? FileManager.default.attributesOfItem(atPath: path)
        let permissions = (attrs?[.posixPermissions] as? NSNumber)?.intValue ?? 0o600
        return Change(path: path, before: before, after: after, permissions: permissions)
    }

    private func plan(_ spec: AgentHookSpec, removing: Bool, codexConfigPath: String?) throws -> [Change] {
        let path = spec.settingsPath
        let before = try read(path)
        let expected = command(for: spec.kind)
        var after: Data?
        switch spec.style {
        case .opencodePlugin, .piExtension:
            let source = spec.style == .piExtension
                ? HookInstaller.piExtension(binary: binaryPath) : HookInstaller.opencodePlugin(binary: binaryPath)
            if let before, before != Data(source.utf8) { throw AgentConnectionError.conflict(path) }
            after = removing ? nil : Data(source.utf8)
        case .jcodeToml:
            guard before == nil || String(data: before!, encoding: .utf8) != nil else {
                throw AgentConnectionError.invalid(path)
            }
            let old = before.flatMap { String(data: $0, encoding: .utf8) } ?? ""
            if old.contains("agentpet"), !old.contains(JcodeHookConfig.tomlString(expected)) {
                throw AgentConnectionError.conflict(path)
            }
            let new = removing ? JcodeHookConfig.uninstall(in: old, events: spec.events)
                : try JcodeHookConfig.install(in: old, command: expected, events: spec.events, path: path)
            after = Data(new.utf8)
        default:
            let old: [String: Any]
            if let before, !before.isEmpty {
                guard let json = try JSONSerialization.jsonObject(with: before) as? [String: Any] else {
                    throw AgentConnectionError.invalid(path)
                }
                old = json
            } else { old = [:] }
            let rootKey = spec.style == .antigravityNested ? HookInstaller.antigravityGroup : "hooks"
            if let value = old[rootKey], !(value is [String: Any]) { throw AgentConnectionError.invalid(path) }
            let eventMap = old[rootKey] as? [String: Any] ?? [:]
            for event in spec.events {
                if let value = eventMap[event], !(value is [[String: Any]]) { throw AgentConnectionError.invalid(path) }
            }
            for value in Self.commands(in: old) where HookInstaller.isOurs(value) && value != expected {
                throw AgentConnectionError.conflict(path)
            }
            var new: [String: Any]
            switch spec.style {
            case .claudeNested:
                for event in spec.events {
                    for group in eventMap[event] as? [[String: Any]] ?? [] {
                        guard group["hooks"] is [[String: Any]] else { throw AgentConnectionError.invalid(path) }
                    }
                }
                new = removing ? HookInstaller.uninstall(from: old, events: spec.events)
                    : HookInstaller.install(into: old, command: expected, events: spec.events)
            case .antigravityNested:
                new = removing ? HookInstaller.uninstallAntigravity(from: old, events: spec.events)
                    : HookInstaller.installAntigravity(into: old, command: expected, events: spec.events)
            default:
                new = removing ? HookInstaller.uninstallFlat(from: old, events: spec.events)
                    : HookInstaller.installFlat(into: old, command: expected, events: spec.events, style: spec.style)
                if !removing, spec.style == .kiroFlat, new["name"] == nil {
                    new["name"] = URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
                }
            }
            // Keep formatting/mtime unchanged on every subsequent launch.
            after = NSDictionary(dictionary: old).isEqual(to: new) ? before
                : try JSONSerialization.data(withJSONObject: new, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        }
        var changes = [Change]()
        if let c = change(path, before, after) { changes.append(c) }
        if !removing, let configPath = codexConfigPath {
            let oldData = try read(configPath)
            guard oldData == nil || String(data: oldData!, encoding: .utf8) != nil else {
                throw AgentConnectionError.invalid(configPath)
            }
            let old = oldData.flatMap { String(data: $0, encoding: .utf8) } ?? ""
            if let updated = CodexHookConfig.enableHooks(in: old),
               let c = change(configPath, oldData, Data(updated.utf8)) { changes.append(c) }
        }
        return changes
    }

    private static func commands(in value: Any) -> [String] {
        if let dict = value as? [String: Any] {
            return dict.flatMap { key, value in
                key == "command" ? (value as? String).map { [$0] } ?? [] : commands(in: value)
            }
        }
        return (value as? [Any])?.flatMap { commands(in: $0) } ?? []
    }

    private func write(_ data: Data?, path: String, permissions: Int) throws {
        let fm = FileManager.default
        if let data {
            try fm.createDirectory(atPath: (path as NSString).deletingLastPathComponent,
                                   withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            try data.write(to: URL(fileURLWithPath: path), options: .atomic)
            try fm.setAttributes([.posixPermissions: permissions], ofItemAtPath: path)
        } else if fm.fileExists(atPath: path) { try fm.removeItem(atPath: path) }
    }

    @discardableResult private func commit(_ changes: [Change]) throws -> Bool {
        guard !changes.isEmpty else { return false }
        let backup = URL(fileURLWithPath: backupRoot).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: backup, withIntermediateDirectories: true,
                                                 attributes: [.posixPermissions: 0o700])
        var manifest: [[String: Any]] = []
        for (index, c) in changes.enumerated() {
            let name = "\(index)-\(URL(fileURLWithPath: c.path).lastPathComponent)"
            if let data = c.before { try write(data, path: backup.appendingPathComponent(name).path, permissions: 0o600) }
            manifest.append(["originalPath": c.path, "existed": c.before != nil, "backupFile": name,
                             "permissions": c.permissions])
        }
        let metadata = try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys])
        try write(metadata, path: backup.appendingPathComponent("restore-info.json").path, permissions: 0o600)
        var written: [Change] = []
        do {
            for c in changes {
                // Don't overwrite another process's edits between planning and committing.
                guard try read(c.path) == c.before else { throw AgentConnectionError.conflict(c.path) }
                written.append(c)
                try write(c.after, path: c.path, permissions: c.permissions)
            }
        } catch {
            for c in written.reversed() {
                // Preserve concurrent changes; backup still contains the original.
                if (try? read(c.path)) == c.after { try? write(c.before, path: c.path, permissions: c.permissions) }
            }
            throw error
        }
        return true
    }
}
