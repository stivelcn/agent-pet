import Foundation
import AppKit
import AgentPetCore

/// Per-window pet state. One instance backs each pet window (single window for
/// now; the registry in later tasks owns one per active project). Holds only
/// the fields that vary per window — global toggles (showChat, petPoint…) still
/// live on `PetController.shared`.
@MainActor
final class PetWindowModel: ObservableObject {
    /// Stable grouping key: a project path or `"default"` for the home pet.
    let key: String

    @Published var petID: String?
    @Published var mood: PetMood
    @Published var projectName: String?
    @Published var sessions: [AgentSession]
    @Published var count: Int
    @Published var chatLine: String
    /// False while this pet's panel is fully occluded or the displays are
    /// asleep/locked. Views pause every animation and timer while false so an
    /// unseen pet costs ~no CPU. Driven by `PetWindowController`.
    @Published var isOnScreen = true
    /// Horizontal shift of the pet inside its window. Non-zero when the window
    /// was pushed back onto the pet's screen (wide bubble near an edge), so the
    /// pet stays put on screen. Driven by `PetWindowController`.
    @Published var petOffset: CGFloat = 0
    /// Current width of this pet's window (content is centred in it).
    @Published var windowWidth: CGFloat = 0

    init(
        key: String,
        petID: String? = nil,
        mood: PetMood = .idle,
        projectName: String? = nil,
        sessions: [AgentSession] = [],
        count: Int = 0,
        chatLine: String = ""
    ) {
        self.key = key
        self.petID = petID
        self.mood = mood
        self.projectName = projectName
        self.sessions = sessions
        self.count = count
        self.chatLine = chatLine
    }

    enum TapDestination: Equatable {
        case none, pairing, composer(String)
    }

    /// No reaction state, timer or sound: a drag must never send the user into messaging.
    func tapDestination(wasDrag: Bool, paired: Bool) -> TapDestination {
        if wasDrag { return .none }
        return paired ? .composer(key) : .pairing
    }
}
