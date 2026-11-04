import AppKit

private final class FlamePanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        // This decorative surface intentionally occupies the camera's top band.
        frameRect
    }
}

/// A single noninteractive surface, anchored to the notch or the top of an external display.
@MainActor
final class NotchFlameController {
    private let settings: NotchFlameSettings
    private let currentDisplay: @MainActor () -> NotchDisplayProfile?
    private var panel: NSPanel?
    private var flameView: NotchFlameMetalView?
    private var observers: [NSObjectProtocol] = []
    private var workspaceObservers: [NSObjectProtocol] = []
    private var lastSpeed: Double = 0
    private var sleeping = false
    private var failed = false

    init(settings: NotchFlameSettings = .shared,
         currentDisplay: @escaping @MainActor () -> NotchDisplayProfile? = { NotchDisplayProfile.current() }) {
        self.settings = settings
        self.currentDisplay = currentDisplay
        observers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshDisplay() }
        })
        observers.append(NotificationCenter.default.addObserver(
            forName: .emberCatFlameSettingsChanged, object: settings, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshVisibility() }
        })
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.screensDidSleepNotification] {
            workspaceObservers.append(NSWorkspace.shared.notificationCenter.addObserver(
                forName: name, object: nil, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.sleeping = true
                    self?.hide()
                }
            })
        }
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification] {
            workspaceObservers.append(NSWorkspace.shared.notificationCenter.addObserver(
                forName: name, object: nil, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.sleeping = false
                    // Wait for the next measured rate instead of replaying pre-sleep output.
                    self?.lastSpeed = 0
                }
            })
        }
    }

    func update(speed: Double) {
        lastSpeed = speed.isFinite ? max(0, speed) : 0
        refreshVisibility()
    }

    private func refreshVisibility() {
        guard settings.isEnabled, !sleeping, !failed else { hide(); return }
        if lastSpeed > 0 {
            if panel == nil || panel?.isVisible != true { refreshDisplay() }
            guard let panel, let flameView else { return }
            flameView.setPalette(settings.palette)
            flameView.setAppearance(settings.appearance)
            flameView.setSpeed(lastSpeed)
            if !panel.isVisible { panel.orderFrontRegardless() }
        } else {
            flameView?.setSpeed(0)
        }
    }

    private func refreshDisplay() {
        guard settings.isEnabled, !sleeping, !failed else { hide(); return }
        guard let profile = currentDisplay() else { hide(); return }
        if panel == nil {
            guard lastSpeed > 0 else { return }
            do {
                let view = try NotchFlameMetalView(geometry: profile.geometry)
                let panel = FlamePanel(contentRect: profile.panelFrame,
                    styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
                panel.title = "EmberCat · 灵动岛火焰"
                panel.isOpaque = false
                panel.backgroundColor = .clear
                panel.hasShadow = false
                panel.ignoresMouseEvents = true
                panel.hidesOnDeactivate = false
                panel.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
                panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
                panel.contentView = view
                view.onFadeOut = { [weak panel] in panel?.orderOut(nil) }
                view.onRenderFailure = { [weak self] in
                    self?.failed = true
                    self?.hide()
                }
                self.panel = panel
                flameView = view
            } catch {
                failed = true
                NSLog("EmberCat flame renderer: %@", error.localizedDescription)
                return
            }
        }
        flameView?.geometry = profile.geometry
        flameView?.setPalette(settings.palette)
        flameView?.setAppearance(settings.appearance)
        flameView?.drawsAnchor = profile.notchFrame == nil
        panel?.setFrame(profile.panelFrame, display: true)
        flameView?.refreshDisplay(maximumFramesPerSecond: profile.maximumFramesPerSecond)
        if lastSpeed > 0 {
            flameView?.setSpeed(lastSpeed)
            panel?.orderFrontRegardless()
        }
    }

    private func hide() {
        flameView?.stop()
        panel?.orderOut(nil)
    }

    func shutdown() {
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        workspaceObservers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
        observers.removeAll()
        workspaceObservers.removeAll()
        hide()
        flameView?.onFadeOut = nil
        flameView?.onRenderFailure = nil
        panel?.contentView = nil
        panel?.close()
        panel = nil
        flameView = nil
    }
}
