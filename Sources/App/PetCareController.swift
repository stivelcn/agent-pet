import Foundation
import AgentPetCore

/// Persistent companions have stable IDs, independent of their sprite packs.
@MainActor
final class PetCareController: ObservableObject {
    static let shared = PetCareController()
    @Published private(set) var archive: PetCompanionArchive
    @Published private(set) var persistenceError: String?
    private let defaults: UserDefaults
    private let notify: Bool
    static let archiveKey = "agentpet.companions.v1"
    private static let storageKey = "agentpet.care.v2"
    private static let legacyKey = "agentpet.care.v1"

    init(defaults: UserDefaults = LocalPreferences.defaults, notify: Bool = true) {
        self.defaults = defaults
        self.notify = notify
        archive = PetCompanionArchive()
        if let stored = defaults.object(forKey: Self.archiveKey) {
            if let data = stored as? Data,
               let saved = try? JSONDecoder().decode(PetCompanionArchive.self, from: data), saved.isValid {
                archive = saved
            } else {
                persistenceError = "养成存档无法读取，已停止写入，原始数据未改动。请先恢复备份。"
            }
            return
        }
        var legacyStates: [String: PetCareState] = [:]
        let selected = defaults.string(forKey: "agentpet.selectedPetID")
        if let stored = defaults.object(forKey: Self.storageKey) {
            guard let data = stored as? Data, let saved = try? JSONDecoder().decode([String: PetCareState].self, from: data) else {
                persistenceError = "旧养成存档无法读取，已停止迁移，原始数据未改动。"
                return
            }
            legacyStates = saved
        } else if let stored = defaults.object(forKey: Self.legacyKey) {
            guard let data = stored as? Data, let saved = try? JSONDecoder().decode(PetCareState.self, from: data) else {
                persistenceError = "旧养成存档无法读取，已停止迁移，原始数据未改动。"
                return
            }
            legacyStates[selected ?? "lulu"] = saved
        }
        archive = .migrate(states: legacyStates, selectedAppearanceID: selected,
                           names: defaults.dictionary(forKey: "agentpet.petNames") as? [String: String] ?? [:])
        // Do not delete or rewrite either legacy preference key.
        persist()
    }

    var states: [String: PetCareState] { archive.states }
    var companions: [PetCompanion] { archive.companions }
    var currentPetID: String? { archive.selectedID }
    var current: PetCareState { state(forCompanionID: currentPetID) }
    var currentAppearanceID: String? { archive.current?.appearanceID }

    func state(forCompanionID id: String?) -> PetCareState {
        id.flatMap { states[$0] } ?? PetCareState()
    }

    /// Window/project callers pass an appearance, never a companion ID.
    func state(for appearanceID: String?) -> PetCareState {
        state(forCompanionID: archive.companionID(forAppearance: appearanceID))
    }

    func appearanceID(forCompanionID id: String) -> String? {
        companions.first { $0.id == id }?.appearanceID
    }

    func name(forCompanionID id: String) -> String {
        guard let companion = companions.first(where: { $0.id == id }) else { return id }
        return companion.name ?? ImagePetStore.shared.pack(id: companion.appearanceID)?.displayName ?? companion.appearanceID
    }

    func changeAppearance(to id: String) {
        guard persistenceError == nil, currentAppearanceID != id else { return }
        if let index = archive.companions.firstIndex(where: { $0.id == currentPetID }),
           archive.companions[index].name == nil {
            let previous = archive.companions[index].appearanceID
            archive.companions[index].name = ImagePetStore.shared.pack(id: previous)?.displayName
                ?? ["lulu": "噜噜", "lumei": "噜妹"][previous] ?? previous
        }
        archive.changeAppearance(to: id)
        persist()
    }

    func selectCompanion(_ id: String) {
        guard persistenceError == nil else { return }
        archive.select(id)
        persist()
    }

    @discardableResult
    func createCompanion(appearanceID: String, name: String) -> String? {
        guard persistenceError == nil, !appearanceID.isEmpty else { return nil }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let defaultName = (ImagePetStore.shared.pack(id: appearanceID)?.displayName ?? appearanceID)
            + " \(companions.count + 1)"
        let id = archive.add(appearanceID: appearanceID, name: trimmed.isEmpty ? defaultName : String(trimmed.prefix(40)))
        persist()
        return id
    }

    func renameCurrent(to name: String) {
        guard persistenceError == nil,
              let index = archive.companions.firstIndex(where: { $0.id == currentPetID }) else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        archive.companions[index].name = trimmed.isEmpty ? nil : String(trimmed.prefix(40))
        persist()
    }

    // MARK: - Derived (selected pet)

    /// Level shown to the user (pet with no XP reads as Lv 0).
    var level: Int { PetCare.displayLevel(forXP: current.xp) }
    var stageKey: String { PetCare.stageName(forLevel: PetCare.level(forXP: current.xp)) }
    var stageIndex: Int { PetCare.stageIndex(forLevel: PetCare.level(forXP: current.xp)) }
    /// Progress through the current level, 0…1.
    var levelProgress: Double { PetCare.progress(forXP: current.xp) }
    var hunger: PetHunger { PetCare.hunger(state: current, now: Date()) }

    /// All raised pets, current first, then by XP.
    var raisedPetIDs: [String] {
        companions.map(\.id).sorted { a, b in
            if a == b { return false }
            if a == currentPetID { return true }
            if b == currentPetID { return false }
            let axp = states[a]?.xp ?? 0, bxp = states[b]?.xp ?? 0
            return axp == bxp ? a < b : axp > bxp
        }
    }

    // MARK: - Feeding

    /// A finished agent session — the pet's proper meal.
    /// Pass `petID` to feed a specific pet (Split ON); `nil` feeds the selected pet (back-compat).
    func recordMeal(petID: String? = nil) {
        mutate(petID: petID) { PetCare.recordMeal(state: &$0, now: Date()) }
    }

    /// Tokens consumed by a Claude turn (transcript usage delta).
    /// Pass `petID` to feed a specific pet (Split ON); `nil` feeds the selected pet (back-compat).
    func feedTokens(_ tokens: Int, petID: String? = nil) {
        guard tokens > 0 else { return }
        mutate(petID: petID) { PetCare.feedTokens(tokens, state: &$0, now: Date()) }
    }

    /// Rolls the daily counters over; UI refresh timers call this so "today"
    /// numbers reset at midnight even with no feeding events.
    func refreshDay() {
        mutate(petID: nil) { PetCare.rollover(&$0, now: Date()) }
    }

    /// Resolves which pet receives a feed: `requested` if it is an installed
    /// pack, otherwise falls back to `selectedPetID`.
    private func resolvedFeedTarget(_ requested: String?) -> String? {
        guard let requested, ImagePetStore.shared.pack(id: requested) != nil else { return currentPetID }
        if let id = archive.companionID(forAppearance: requested) { return id }
        // A configured split-project pet may never have received a meal yet.
        let selected = currentPetID
        let id = archive.add(appearanceID: requested)
        if let selected { archive.select(selected) }
        return id
    }

    private func mutate(petID requested: String?, _ change: (inout PetCareState) -> Void) {
        guard persistenceError == nil, let petID = resolvedFeedTarget(requested) else { return }
        let stateBefore = state(forCompanionID: petID)
        let levelBefore = PetCare.level(forXP: stateBefore.xp)
        let achievementsBefore = stateBefore.unlockedAchievements ?? []
        var s = stateBefore
        change(&s)
        // Reconcile achievements after every feed/meal/rollover: recordMeal and
        // feedTokens mutate the stats but don't unlock badges themselves, so
        // without this the unlock set stays empty forever (HUD showed 0/14).
        PetCare.unlockNewAchievements(state: &s, now: Date())
        guard s != states[petID] else { return }
        archive.states[petID] = s
        persist()
        guard notify else { return }
        let appearanceID = appearanceID(forCompanionID: petID)
        let levelAfter = PetCare.level(forXP: s.xp)
        if levelAfter > levelBefore {
            let line = String(
                format: NSLocalizedString("Level up! Lv %d ⭐", comment: "pet level-up celebrate line"),
                PetCare.displayLevel(forXP: s.xp)
            )
            PetController.shared.flashLevelUp(line: line, petID: appearanceID)
        }
        let achievementsAfter = s.unlockedAchievements ?? []
        let newAchievements = achievementsAfter.subtracting(achievementsBefore)
        if newAchievements.count > 3 {
            // Bulk backfill (first run after the feature shipped, or a veteran
            // pet): one summary line instead of a burst of celebrate flashes.
            let line = String(
                format: NSLocalizedString("%d achievements unlocked! 🏆", comment: "bulk achievement unlock celebrate line"),
                newAchievements.count
            )
            PetController.shared.flashCelebrate(line: line, petID: appearanceID)
        } else {
            for achievement in newAchievements {
                let name = PetCare.achievementDisplayName(achievement)
                let line = String(
                    format: NSLocalizedString("Achievement unlocked: %@ 🏆", comment: "achievement unlock celebrate line"),
                    name
                )
                PetController.shared.flashCelebrate(line: line, petID: appearanceID)
            }
        }
    }

    /// All achievements unlocked by the currently selected pet.
    var achievements: Set<Achievement> { current.unlockedAchievements ?? [] }

    func saveForUpdate() throws {
        persist()
        guard persistenceError == nil else { throw AppUpdateError.message("User data could not be saved. Installation was stopped.") }
    }

    private func persist() {
        guard persistenceError == nil else { return }
        guard archive.isValid else {
            persistenceError = "养成存档结构不完整，已停止写入，原始数据未改动。"
            return
        }
        do {
            let data = try JSONEncoder().encode(archive)
            defaults.set(data, forKey: Self.archiveKey)
        } catch {
            persistenceError = "养成存档保存失败，原始数据未改动。"
        }
    }
}

/// Care-driven chatter: hunger and near-limit anxiety colour the idle pool.
enum CareChat {
    static let hungry = [
        "Getting hungry… run an agent?",
        "A little snack? One small task?",
        "My tummy is rumbling…",
        "Feed me some tokens, please.",
    ]

    static let starving = [
        "Starving… nothing to eat for days…",
        "So weak… one tiny session, please…",
        "No tokens… no energy…",
        "Remember me? Your pet? The hungry one?",
    ]

    static let anxious = [
        "Careful… your AI budget is almost gone.",
        "Low fuel: a usage limit is nearly reached!",
        "Maybe save some tokens for tomorrow…",
    ]

    /// Mixes care lines into the idle pool: starving replaces it entirely,
    /// hungry and limit-anxiety blend in.
    @MainActor
    static func idlePool(base: [String], hunger: PetHunger? = nil) -> [String] {
        var pool = base
        let h = hunger ?? PetCareController.shared.hunger
        switch h {
        case .starving:
            pool = starving.map { NSLocalizedString($0, comment: "starving pet line") }
        case .hungry:
            pool += hungry.map { NSLocalizedString($0, comment: "hungry pet line") }
        default:
            break
        }
        return pool
    }
}
