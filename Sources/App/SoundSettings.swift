import AppKit
import AgentPetCore

/// Plays a sound when an agent finishes or needs input. Each event has its own
/// on/off and sound choice (a built-in macOS system sound, or a custom file the
/// user uploads). Custom files are copied into `AgentPetPaths.baseDir/sounds/`.
@MainActor
final class SoundSettings: ObservableObject {
    static let shared = SoundSettings()

    enum Event: String { case waiting, done }

    private var playingSounds: [Event: NSSound] = [:]
    private let isSleeping: @MainActor () -> Bool

    @Published var waitingEnabled: Bool { didSet { save() } }
    @Published var doneEnabled: Bool { didSet { save() } }
    /// "" means use the built-in default; otherwise a custom file path.
    @Published var waitingCustomPath: String { didSet { save() } }
    @Published var doneCustomPath: String { didSet { save() } }

    /// Built-in macOS system sounds used as defaults.
    static let defaultWaiting = "Submarine"
    static let defaultDone = "Glass"

    private var soundsDir: URL {
        URL(fileURLWithPath: AgentPetPaths.baseDir).appendingPathComponent("sounds")
    }

    init(isSleeping: @escaping @MainActor () -> Bool = { PetSleepController.shared.isSleeping }) {
        self.isSleeping = isSleeping
        let d = LocalPreferences.defaults
        waitingEnabled = (d.object(forKey: "agentpet.sound.waiting.on") as? Bool) ?? true
        doneEnabled = (d.object(forKey: "agentpet.sound.done.on") as? Bool) ?? true
        waitingCustomPath = d.string(forKey: "agentpet.sound.waiting.path") ?? ""
        doneCustomPath = d.string(forKey: "agentpet.sound.done.path") ?? ""
    }

    func isEnabled(_ event: Event) -> Bool {
        event == .waiting ? waitingEnabled : doneEnabled
    }

    func customPath(_ event: Event) -> String {
        event == .waiting ? waitingCustomPath : doneCustomPath
    }

    /// Plays the configured sound for an event, if enabled.
    func play(_ event: Event) {
        guard canPlay(event) else { return }
        let sound: NSSound?
        let path = customPath(event)
        if !path.isEmpty, FileManager.default.fileExists(atPath: path) {
            sound = NSSound(contentsOfFile: path, byReference: true)
        } else {
            sound = NSSound(named: event == .waiting ? Self.defaultWaiting : Self.defaultDone)
        }
        playingSounds[event]?.stop()
        playingSounds[event] = sound
        sound?.play()
    }

    func canPlay(_ event: Event) -> Bool { isEnabled(event) && !isSleeping() }

    func silence() {
        playingSounds.values.forEach { $0.stop() }
        playingSounds.removeAll()
    }

    /// Prompts for an audio file and sets it as the custom sound for an event.
    func upload(for event: Event) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.audio]
        panel.allowsMultipleSelection = false
        panel.prompt = NSLocalizedString("Choose", comment: "sound file picker")
        panel.message = NSLocalizedString("Choose a sound file", comment: "sound file picker")
        guard panel.runModal() == .OK, let url = panel.url else { return }

        let fm = FileManager.default
        try? fm.createDirectory(at: soundsDir, withIntermediateDirectories: true)
        let dest = soundsDir.appendingPathComponent("\(event.rawValue).\(url.pathExtension)")
        try? fm.removeItem(at: dest)
        do {
            try fm.copyItem(at: url, to: dest)
        } catch {
            return
        }
        setCustomPath(dest.path, for: event)
        play(event)   // preview
    }

    func resetToDefault(_ event: Event) {
        setCustomPath("", for: event)
    }

    private func setCustomPath(_ path: String, for event: Event) {
        if event == .waiting { waitingCustomPath = path } else { doneCustomPath = path }
    }

    private func save() {
        let d = LocalPreferences.defaults
        d.set(waitingEnabled, forKey: "agentpet.sound.waiting.on")
        d.set(doneEnabled, forKey: "agentpet.sound.done.on")
        d.set(waitingCustomPath, forKey: "agentpet.sound.waiting.path")
        d.set(doneCustomPath, forKey: "agentpet.sound.done.path")
    }
}
