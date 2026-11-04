import Foundation

/// A companion owns its progress; an appearance is only the outfit it wears.
public struct PetCompanion: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public var appearanceID: String
    public var name: String?

    public init(id: String, appearanceID: String, name: String? = nil) {
        self.id = id
        self.appearanceID = appearanceID
        self.name = name
    }
}

/// One atomic preferences value for identity, selection and complete care state.
/// Legacy care dictionaries remain untouched for recovery/rollback.
public struct PetCompanionArchive: Codable, Equatable, Sendable {
    public var version = 1
    public var selectedID: String?
    public var companions: [PetCompanion] = []
    public var states: [String: PetCareState] = [:]

    public init() {}

    public var current: PetCompanion? { companions.first { $0.id == selectedID } }
    public var isValid: Bool {
        version == 1 && Set(companions.map(\.id)).count == companions.count
            && companions.allSatisfy { !$0.id.isEmpty && !$0.appearanceID.isEmpty }
            && (companions.isEmpty ? selectedID == nil : current != nil)
            && Set(states.keys).isSubset(of: Set(companions.map(\.id)))
    }

    public static func migrate(states: [String: PetCareState], selectedAppearanceID: String?,
                               names: [String: String]) -> Self {
        var result = Self()
        result.states = states
        result.companions = states.keys.sorted().map {
            PetCompanion(id: $0, appearanceID: $0, name: names[$0])
        }
        // Recover the raised companion when an old appearance switch selected
        // a never-fed skin. Never add together or overwrite independent histories.
        let ranked = states.keys.sorted {
            if states[$0]!.xp != states[$1]!.xp { return states[$0]!.xp > states[$1]!.xp }
            return $0 < $1
        }
        let raised = ranked.first { hasProgress(states[$0]!) }
        if let appearance = selectedAppearanceID {
            if let selectedState = states[appearance], hasProgress(selectedState) {
                result.selectedID = appearance
            } else if let raised {
                result.selectedID = raised
                result.changeAppearance(to: appearance)
            } else if states[appearance] != nil {
                result.selectedID = appearance
            } else {
                result.add(appearanceID: appearance, name: names[appearance], id: appearance)
            }
        } else {
            result.selectedID = raised ?? ranked.first
        }
        return result
    }

    private static func hasProgress(_ state: PetCareState) -> Bool {
        state.xp > 0 || state.totalTokens > 0 || state.totalMeals > 0
            || state.lastFedAt != nil || !(state.unlockedAchievements ?? []).isEmpty
    }

    public mutating func changeAppearance(to appearanceID: String) {
        guard !appearanceID.isEmpty else { return }
        guard let index = companions.firstIndex(where: { $0.id == selectedID }) else {
            add(appearanceID: appearanceID)
            return
        }
        companions[index].appearanceID = appearanceID
    }

    @discardableResult
    public mutating func add(appearanceID: String, name: String? = nil,
                             id: String = UUID().uuidString) -> String {
        guard !appearanceID.isEmpty, !id.isEmpty, !companions.contains(where: { $0.id == id }) else {
            return selectedID ?? ""
        }
        companions.append(PetCompanion(id: id, appearanceID: appearanceID, name: name))
        states[id] = PetCareState()
        selectedID = id
        return id
    }

    public mutating func select(_ id: String) {
        guard companions.contains(where: { $0.id == id }) else { return }
        selectedID = id
    }

    /// Compatibility for project/window APIs that still address appearance IDs.
    /// The current companion wins when wearing that appearance. Otherwise keep
    /// an existing matching/legacy identity, rather than redirecting its history.
    public func companionID(forAppearance appearanceID: String?) -> String? {
        guard let appearanceID else { return selectedID }
        if current?.appearanceID == appearanceID { return selectedID }
        return companions.first { $0.id == appearanceID && $0.appearanceID == appearanceID }?.id
            ?? companions.first { $0.appearanceID == appearanceID }?.id
            ?? companions.first { $0.id == appearanceID }?.id
    }
}
