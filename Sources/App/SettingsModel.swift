import AppKit
import Foundation
@preconcurrency import UserNotifications
import AgentPetCore

/// Backs the onboarding/Settings window: notification permission status and
/// per-agent hook install state, with the actions to change them.
@MainActor
final class SettingsModel: ObservableObject {
    static let shared = SettingsModel()

    enum NotificationState: Equatable {
        case unavailable   // running as bare binary, no bundle
        case notDetermined
        case enabled
        case denied
    }

    @Published private(set) var notificationState: NotificationState = .notDetermined
    @Published private(set) var installedKinds: Set<AgentKind> = []
    /// Surfaced when an install/uninstall fails (e.g. an agent's settings file is
    /// not valid JSON), so the user sees why instead of a silent no-op.
    @Published var installError: String?

    /// In-app notification toggle: lets users mute alerts even after granting
    /// the macOS permission. Defaults to on.
    @Published var notificationsEnabled: Bool {
        didSet { LocalPreferences.defaults.set(notificationsEnabled, forKey: NotificationManager.enabledKey) }
    }

    /// Backed by `AgentPetPaths.baseDir/approval-gate.json` so the separate hook CLI process reads it too.
    @Published var approvalGateEnabled: Bool {
        didSet { ApprovalGateConfig.setEnabled(approvalGateEnabled) }
    }

    let agents = AgentCatalog.all

    init() {
        notificationsEnabled = (LocalPreferences.defaults.object(forKey: NotificationManager.enabledKey) as? Bool) ?? true
        approvalGateEnabled = ApprovalGateConfig.isEnabled()
    }

    @Published private(set) var detectedClients: [AgentKind: String] = [:]
    @Published private(set) var connectionErrors: [AgentKind: String] = [:]
    @Published private(set) var lastEvents: [AgentKind: Date] = [:]
    private static let disconnectedKey = "agentpet.disconnectedClients"
    private var disconnected: Set<String> = Set(LocalPreferences.defaults.stringArray(forKey: disconnectedKey) ?? [])

    private var installer: AgentConnectionInstaller {
        AgentConnectionInstaller(
            binaryPath: Bundle.main.executablePath ?? CommandLine.arguments[0],
            backupRoot: AgentPetPaths.baseDir + "/config-backups")
    }

    /// Run only after the local event receiver has started. Configuration is not a live connection.
    func autoConnectDetectedClients() {
        refresh()
        guard LocalConfiguration.hookConfigurationEnabled,
              ProcessInfo.processInfo.environment["AGENTPET_AUTOCONNECT"] != "0" else { return }
        for agent in agents where agent.isSupported && detectedClients[agent.kind] != nil {
            guard !disconnected.contains(agent.kind.rawValue) else { continue }
            connect(agent.kind)
        }
        refresh()
    }

    func refresh() {
        detectedClients = AgentClientDetector.detect()
        installedKinds = Set(agents.compactMap { agent in
            guard agent.isSupported, let spec = AgentHooks.spec(for: agent.kind),
                  installer.isConfigured(spec, codexConfigPath: agent.kind == .codex ? CodexHookConfig.defaultConfigPath() : nil)
            else { return nil }
            return agent.kind
        })
        refreshNotificationState()
    }

    func isInstalled(_ kind: AgentKind) -> Bool { installedKinds.contains(kind) }

    func connectionStatus(_ kind: AgentKind) -> String {
        if let error = connectionErrors[kind] { return error }
        if let date = lastEvents[kind] {
            return "已收到客户端事件 · " + date.formatted(date: .omitted, time: .standard)
        }
        if isInstalled(kind) { return "已配置，等待客户端事件" }
        if disconnected.contains(kind.rawValue) { return "已断开，不会自动重连" }
        return detectedClients[kind] == nil ? "未检测到已安装的客户端" : "已检测到，尚未连接"
    }

    func recordActivity(_ kind: AgentKind) {
        lastEvents[kind] = Date()
    }

    private func connect(_ kind: AgentKind) {
        guard let spec = AgentHooks.spec(for: kind) else { return }
        connectionErrors.removeValue(forKey: kind)
        do {
            try installer.connect(spec, codexConfigPath: kind == .codex ? CodexHookConfig.defaultConfigPath() : nil)
        } catch {
            connectionErrors[kind] = error.localizedDescription
            installError = error.localizedDescription
        }
    }

    func toggleInstall(_ kind: AgentKind) {
        guard LocalConfiguration.hookConfigurationEnabled else {
            installError = "当前启动方式已关闭客户端配置；请正常启动开发版后重试。"
            return
        }
        guard let spec = AgentHooks.spec(for: kind) else { return }
        installError = nil
        connectionErrors.removeValue(forKey: kind)
        if isInstalled(kind) {
            do {
                try installer.disconnect(spec)
                disconnected.insert(kind.rawValue)
                lastEvents.removeValue(forKey: kind)
            } catch {
                connectionErrors[kind] = error.localizedDescription
                installError = error.localizedDescription
            }
        } else {
            guard detectedClients[kind] != nil else { return }
            connect(kind)
            if connectionErrors[kind] == nil { disconnected.remove(kind.rawValue) }
        }
        LocalPreferences.defaults.set(Array(disconnected).sorted(), forKey: Self.disconnectedKey)
        refresh()
    }

    func enableNotifications() {
        guard NotificationManager.shared.isAvailable else { return }
        Task { @MainActor in
            _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
            self.refreshNotificationState()
        }
    }

    /// Opens System Settings to AgentPet's notification pane (used when denied).
    func openSystemNotificationSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.notifications") {
            NSWorkspace.shared.open(url)
        }
    }

    private func refreshNotificationState() {
        guard NotificationManager.shared.isAvailable else {
            notificationState = .unavailable
            return
        }
        Task { @MainActor in
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            switch settings.authorizationStatus {
            case .authorized, .provisional, .ephemeral:
                self.notificationState = .enabled
            case .denied:
                self.notificationState = .denied
            default:
                self.notificationState = .notDetermined
            }
        }
    }
}
