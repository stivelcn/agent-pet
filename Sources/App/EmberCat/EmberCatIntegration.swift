import AppKit
import Combine
import AgentPetCore
import AgentSpeedCore

/// A single in-process monitor drives the original flame renderer and AgentPet's existing paw.
/// It never writes AgentPet's usage/care ledger, installs hooks, or enables upstream reporting.
@MainActor
final class EmberCatIntegration: ObservableObject {
    static let shared: EmberCatIntegration = {
        let defaults = LocalPreferences.defaults
        if EmberCatPreferenceMigration.allowsLegacyImport(environment: ProcessInfo.processInfo.environment) {
            EmberCatPreferenceMigration.importOnce(
                source: UserDefaults.standard.persistentDomain(forName: EmberCatPreferenceMigration.sourceDomain),
                into: defaults)
        }
        return EmberCatIntegration(defaults: defaults)
    }()

    let flameSettings: NotchFlameSettings
    private let defaults: UserDefaults
    private let store = SpeedStore()
    private var monitor: LiveMonitor?
    private var liveToken: UUID?
    private var flame: NotchFlameController?
    private var settingsObserver: NSObjectProtocol?
    private(set) var isRunning = false
    var onMenuBarChange: (() -> Void)?

    @Published private(set) var snapshot: SpeedSnapshot = .empty
    @Published private(set) var flameEnabled: Bool
    @Published var showsTokenRate: Bool {
        didSet {
            defaults.set(showsTokenRate, forKey: "showsTokenRate")
            onMenuBarChange?()
        }
    }
    @Published var ratePrecision: Int {
        didSet {
            defaults.set(min(2, max(0, ratePrecision)), forKey: "agentpet.embercat.ratePrecision")
            onMenuBarChange?()
        }
    }

    init(defaults: UserDefaults) {
        self.defaults = defaults
        flameSettings = NotchFlameSettings(defaults: defaults)
        flameEnabled = flameSettings.isEnabled
        showsTokenRate = defaults.object(forKey: "showsTokenRate") as? Bool ?? true
        ratePrecision = min(2, max(0, defaults.object(forKey: "agentpet.embercat.ratePrecision") as? Int ?? 1))
        settingsObserver = NotificationCenter.default.addObserver(
            forName: .emberCatFlameSettingsChanged, object: flameSettings, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.flameEnabled = self.flameSettings.isEnabled
            }
        }
    }

    var speed: Double { snapshot.live.output.isFinite ? max(0, snapshot.live.output) : 0 }
    var estimatedShare: Double {
        snapshot.liveEstimatedShare.isFinite ? min(1, max(0, snapshot.liveEstimatedShare)) : 0
    }
    var menuBarText: String {
        guard showsTokenRate else { return "" }
        guard snapshot.state == .running else { return "— t/s" }
        return EmberCatRateFormat.text(speed: speed, precision: ratePrecision, compactUnit: true)
    }
    var statusLine: String {
        switch snapshot.state {
        case .starting(let progress):
            let percent = Int((min(1, max(0, progress.isFinite ? progress : 0)) * 100).rounded())
            return "正在扫描本地会话 · \(percent)%"
        case .noSources: return "尚未发现可读取的编程助手会话"
        case .running:
            if speed > 0 { return "正在输出 · \(snapshot.generatingCount) 个生成中的会话" }
            if snapshot.toolsCount > 0 { return "工具执行中 · 当前没有 token 输出" }
            return "待机 · 等待编程助手输出"
        }
    }
    var estimateDescription: String {
        estimatedShare > 0
            ? String(format: "当前速度中约 %.0f%% 为进行中估算", estimatedShare * 100)
            : "当前速度不含进行中估算"
    }

    func setFlameEnabled(_ enabled: Bool) { flameSettings.isEnabled = enabled }

    func setPresentationSuppressed(_ suppressed: Bool) {
        flame?.setPresentationSuppressed(suppressed)
    }

    func start(environment: [String: String] = ProcessInfo.processInfo.environment) {
        guard !isRunning, environment["AGENTPET_EMBERCAT_ENABLED"] != "0" else { return }
        isRunning = true
        flame = NotchFlameController(settings: flameSettings,
                                   presentationSuppressed: PetSleepController.shared.isSleeping)
        liveToken = store.addLiveListener { [weak self] snapshot in self?.receive(snapshot) }
        // Same source set and live-output window as EmberCat v0.6.15. No demo driver or network client.
        let monitor = LiveMonitor(store: store,
                                  configuration: MonitorConfiguration(enabledSources: Set(SourceKind.allCases)))
        self.monitor = monitor
        monitor.start()
    }

    /// Kept separate from startup so tests can use synthetic snapshots without reading real transcripts.
    func receive(_ snapshot: SpeedSnapshot) {
        self.snapshot = snapshot
        flame?.update(speed: snapshot.state == .running ? speed : 0)
        onMenuBarChange?()
    }

    func stop() {
        monitor?.stop()
        monitor = nil
        if let liveToken { store.removeLiveListener(liveToken) }
        liveToken = nil
        flame?.shutdown()
        flame = nil
        isRunning = false
        snapshot = .empty
        onMenuBarChange?()
    }

    func dispose() {
        stop()
        if let settingsObserver { NotificationCenter.default.removeObserver(settingsObserver) }
        settingsObserver = nil
        onMenuBarChange = nil
    }
}
