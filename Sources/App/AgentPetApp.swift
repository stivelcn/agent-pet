import SwiftUI
import AppKit
import AgentPetCore

struct AgentPetApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // The UI lives in a status-item popover and floating windows managed by
        // AppDelegate; this scene only satisfies the App protocol. It used to be
        // `Settings { EmptyView() }`, which macOS 26 presents at launch (and on
        // ⌘,) as a blank "AgentPet Settings" window. A never-inserted
        // MenuBarExtra owns no window, so nothing blank can appear.
        // simplify: `.defaultLaunchBehavior(.suppressed)` is the direct fix once
        // the deployment target reaches macOS 15.
        MenuBarExtra(LocalConfiguration.displayName, isInserted: .constant(false)) { EmptyView() }
            .commands {
                // Keep the app menu's "Settings…" (⌘,) and route it to the real
                // Settings window.
                CommandGroup(replacing: .appSettings) {
                    Button {
                        SettingsWindowController.shared.show()
                    } label: {
                        // Reuses the existing "Settings" translation.
                        Text(NSLocalizedString("Settings", comment: "app menu") + "…")
                    }
                    .keyboardShortcut(",", modifiers: .command)
                }
            }
    }
}

/// Runs the app as a menu bar accessory (no Dock icon) and boots the daemon.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        _ = AppLanguage.shared   // apply the saved language before any UI renders
        // Load only the selected pet up front so the menu bar + pet appear at
        // once; the rest of the library slices in on later run-loop ticks.
        ImagePetStore.shared.loadFast(priorityID: PetController.shared.selectedPetID)
        if PetController.shared.selectedPetID == nil {
            PetController.shared.selectedPetID = ImagePetStore.shared.packs.first?.id
        }
        // Agent brand icons aren't needed for first paint; warm them after launch.
        Task { @MainActor in AgentIcons.prewarm() }
        PetController.shared.start()
        PetWindowController.shared.start()
        AppDaemon.shared.start()
        SettingsModel.shared.autoConnectDetectedClients()
        BreakReminderController.shared.start()
        StatusBarController.shared.start()
        EmberCatIntegration.shared.start()
        PetRelayController.shared.start()
        SettingsWindowController.shared.showOnFirstLaunch()
    }

    func applicationWillTerminate(_ notification: Notification) {
        PetRelayController.shared.stop()
        EmberCatSettingsWindowController.shared.shutdown()
        EmberCatIntegration.shared.dispose()
    }

}
