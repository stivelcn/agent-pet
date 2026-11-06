import Foundation
import Combine
import SwiftUI
import AgentPetCore

/// A presentation pause only. Mail, completion notices and background tracking keep running.
@MainActor
final class PetSleepController: ObservableObject {
    static let preferenceKey = "agentpet.petSleeping"
    static let shared = PetSleepController(defaults: LocalPreferences.defaults) { sleeping in
        PetWindowController.shared.applySleepState(sleeping)
        StatusBarController.shared.applySleepState(sleeping)
        EmberCatIntegration.shared.setPresentationSuppressed(sleeping)
        if sleeping {
            NotificationManager.shared.hideNotifications()
            SoundSettings.shared.silence()
            BreakReminderController.shared.silence()
            _ = PetRelayController.shared.consumeInteractionBatch(canAnimate: false)
        }
    }

    @Published private(set) var isSleeping: Bool
    private let defaults: UserDefaults
    private let onChange: @MainActor (Bool) -> Void

    init(defaults: UserDefaults, onChange: @escaping @MainActor (Bool) -> Void = { _ in }) {
        self.defaults = defaults
        self.onChange = onChange
        isSleeping = defaults.bool(forKey: Self.preferenceKey)
    }

    func goToSleep() { setSleeping(true) }
    func wakeUp() { setSleeping(false) }

    private func setSleeping(_ sleeping: Bool) {
        guard isSleeping != sleeping else { return }
        isSleeping = sleeping
        defaults.set(sleeping, forKey: Self.preferenceKey)
        onChange(sleeping)
    }
}

/// Shared action used by the pet's right-click card and the menu bar dropdown.
struct PetSleepButton: View {
    @ObservedObject var sleep: PetSleepController = .shared
    @ObservedObject private var language = AppLanguage.shared
    var dismiss: () -> Void = {}

    var body: some View {
        Button {
            dismiss()
            if sleep.isSleeping { sleep.wakeUp() } else { sleep.goToSleep() }
        } label: {
            Label(NSLocalizedString(sleep.isSleeping ? "Leave the nest and get to work" : "Back to the nest to sleep",
                                    comment: "pet sleep action"),
                  systemImage: sleep.isSleeping ? "sun.max.fill" : "moon.zzz.fill")
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .accessibilityIdentifier(sleep.isSleeping ? "pet-wake-up" : "pet-go-to-sleep")
        .environment(\.locale, language.locale)
    }
}
