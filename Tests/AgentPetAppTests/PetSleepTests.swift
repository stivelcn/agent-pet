import AppKit
import SwiftUI
import Testing
@testable import AgentPetCore
@testable import agentpet

@MainActor
@Suite(.serialized)
struct PetSleepTests {
    private func withSleep(_ body: (PetSleepController, UserDefaults) throws -> Void) rethrows {
        let suite = "local.agentpet.tests.sleep.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        try body(PetSleepController(defaults: defaults), defaults)
    }

    @Test func sleepPersistsAcrossRestartAndRepeatedActionsAreIdempotent() {
        withSleep { sleep, defaults in
            #expect(!sleep.isSleeping)
            var changes: [Bool] = []
            let observed = PetSleepController(defaults: defaults) { value in
                // Side effects must observe the committed state, including after a restart.
                #expect(PetSleepController(defaults: defaults).isSleeping == value)
                changes.append(value)
            }
            observed.goToSleep()
            observed.goToSleep()
            #expect(PetSleepController(defaults: defaults).isSleeping)
            observed.wakeUp()
            observed.wakeUp()
            #expect(!PetSleepController(defaults: defaults).isSleeping)
            #expect(changes == [true, false])
        }
    }

    @Test func splitWindowsStayHiddenThroughSyncAppearanceChangesAndVisibilityToggle() {
        _ = NSApplication.shared
        withSleep { sleep, _ in
            sleep.goToSleep()
            let windows = PetWindowController(isSleeping: { sleep.isSleeping })
            defer { windows.sync(specs: []) { _ in fatalError("No specs") } }
            let previous = Set(NSApp.windows.map(ObjectIdentifier.init))
            let specs = [PetWindowPlanner.defaultKey, "/isolated/sleep-project"].map {
                PetWindowSpec(key: $0, projectName: "隔离项目", petID: "lulu", sessionIDs: [], mood: .idle, count: 0)
            }
            for id in ["lulu", "lumei"] {
                windows.sync(specs: specs) { _ in
                    PetWindowController.WindowState(petID: id, mood: .working, sessions: [], count: 1, chatLine: "新消息")
                }
                windows.isVisible = false
                windows.isVisible = true
                windows.applySleepState(true)
                windows.showMessageComposer()
                #expect(!windows.canPresentPets)
                #expect(specs.allSatisfy { windows.displayedPetID(forKey: $0.key) == id })
                let created = NSApp.windows.filter { !previous.contains(ObjectIdentifier($0)) }
                #expect(created.count >= 2)
                #expect(created.allSatisfy { !$0.isVisible && !$0.isKeyWindow })
            }
            // Verify wake policy after removing test panels, keeping the user's desktop undisturbed.
            windows.sync(specs: []) { _ in fatalError("No specs") }
            sleep.wakeUp()
            windows.applySleepState(false)
            #expect(windows.canPresentPets && windows.isVisible)
        }
    }

    @Test func sleepMutesAlertsWithoutChangingNotificationOrSoundPreferences() {
        withSleep { sleep, _ in
            let defaults = LocalPreferences.defaults
            let keys = [NotificationManager.enabledKey, "agentpet.sound.waiting.on", "agentpet.sound.done.on",
                        "agentpet.sound.waiting.path", "agentpet.sound.done.path"]
            let saved = keys.map { defaults.object(forKey: $0) }
            defer {
                for (key, value) in zip(keys, saved) {
                    if let value { defaults.set(value, forKey: key) }
                    else { defaults.removeObject(forKey: key) }
                }
            }
            defaults.set(true, forKey: NotificationManager.enabledKey)
            let notifications = NotificationManager(isAvailable: true, isSleeping: { sleep.isSleeping })
            let sounds = SoundSettings(isSleeping: { sleep.isSleeping })
            sounds.waitingEnabled = true
            sounds.doneEnabled = false
            #expect(notifications.canNotify && sounds.canPlay(.waiting))
            sleep.goToSleep()
            #expect(!notifications.canNotify && !sounds.canPlay(.waiting) && !sounds.canPlay(.done))
            notifications.notify(title: "隔离测试", body: "不能显示")
            sounds.play(.waiting) // Must return before creating or playing any NSSound.
            #expect(notifications.userEnabled && sounds.waitingEnabled && !sounds.doneEnabled)
            sleep.wakeUp()
            #expect(notifications.canNotify && sounds.canPlay(.waiting) && !sounds.canPlay(.done))
        }
    }

    @Test func unreadCompletionsKeepRecordingAndSurviveSleepAndWake() {
        withSleep { sleep, _ in
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent("sleep-notices-\(UUID().uuidString)")
            defer { try? FileManager.default.removeItem(at: directory) }
            let file = directory.appendingPathComponent("notices.json")
            let notices = CompletionNoticeStore(fileURL: file)
            sleep.goToSleep()
            let now = Date()
            notices.record(AgentSession(id: "sleep-completion", agentKind: .codex, project: "/isolated/project",
                state: .done, source: .hook, updatedAt: now, stateSince: now), at: now)
            let before = notices.notices
            #expect(before.count == 1)
            sleep.wakeUp()
            #expect(notices.notices == before)
            #expect(CompletionNoticeStore(fileURL: file).notices == before)
        }
    }

    @Test func flameSuppressionKeepsRateUpdatesAndPreferencesWithoutCreatingAnOverlay() {
        withSleep { _, defaults in
            let settings = NotchFlameSettings(defaults: defaults)
            var displayRequests = 0
            let flames = NotchFlameController(settings: settings, presentationSuppressed: true) {
                displayRequests += 1
                return nil // Never create an on-screen test overlay.
            }
            defer { flames.shutdown() }
            flames.update(speed: 120)
            settings.isEnabled = false
            settings.isEnabled = true
            #expect(flames.presentationSuppressed && displayRequests == 0)
            #expect(settings.isEnabled)
            flames.setPresentationSuppressed(false)
            #expect(!flames.presentationSuppressed && displayRequests > 0)
            #expect(settings.isEnabled)
        }
    }

    @Test func chineseSleepAndWakeActionsRenderOffscreen() throws {
        _ = NSApplication.shared
        try withSleep { sleep, _ in
            try withChineseSnapshot {
                for sleeping in [false, true] {
                    if sleeping { sleep.goToSleep() }
                    let key = sleeping ? "Leave the nest and get to work" : "Back to the nest to sleep"
                    #expect(NSLocalizedString(key, comment: "") == (sleeping ? "出窝搬砖" : "回窝睡觉"))
                    let view = Group {
                        if sleeping { MenuContentView(sleep: sleep, dismiss: {}) }
                        else { PetStatsView(petID: "lulu", sleep: sleep) }
                    }.environment(\.animationsEnabled, false).preferredColorScheme(.dark)
                    let host = NSHostingView(rootView: view)
                    host.frame = NSRect(origin: .zero, size: host.fittingSize)
                    let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
                    window.contentView = host
                    host.layoutSubtreeIfNeeded()
                    #expect(!window.isVisible && !window.isKeyWindow)
                    let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
                    host.cacheDisplay(in: host.bounds, to: bitmap)
                    if let path = ProcessInfo.processInfo.environment["AGENTPET_UI_SNAPSHOT_DIR"] {
                        let folder = URL(fileURLWithPath: path)
                        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                        try #require(bitmap.representation(using: .png, properties: [:]))
                            .write(to: folder.appendingPathComponent(sleeping ? "pet-wake-up.png" : "pet-go-to-sleep.png"))
                    }
                    window.contentView = nil
                }
            }
        }
    }
}
