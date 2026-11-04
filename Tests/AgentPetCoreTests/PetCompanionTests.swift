import Foundation
import Testing
@testable import AgentPetCore

struct PetCompanionTests {
    /// Isolated synthetic history; never installed in real app preferences.
    private func raisedState() -> PetCareState {
        var state = PetCareState()
        state.xp = 3560
        state.tokenCarry = 314
        state.tokensToday = 50_000
        state.totalTokens = 12_176_408
        state.mealsToday = 3
        state.totalMeals = 45
        state.lastFedAt = Date(timeIntervalSince1970: 1_793_750_000)
        state.dayKey = "2026-11-04"
        state.streakDays = 8
        state.lastFedDayKey = "2026-11-04"
        state.days = ["2026-11-03": 20_000, "2026-11-04": 50_000]
        state.unlockedAchievements = [.firstMeal, .level5, .streak7]
        return state
    }

    @Test func appearanceSwitchKeepsEveryCareFieldAndIdentityAcrossReload() throws {
        let state = raisedState()
        var archive = PetCompanionArchive.migrate(states: ["lulu": state],
            selectedAppearanceID: "lulu", names: ["lulu": "我的噜噜"])
        for appearance in ["lumei", "jubao", "lulu", "lumei"] {
            archive.changeAppearance(to: appearance)
            archive = try JSONDecoder().decode(PetCompanionArchive.self, from: JSONEncoder().encode(archive))
            #expect(archive.isValid)
            #expect(archive.selectedID == "lulu")
            #expect(archive.current?.appearanceID == appearance)
            #expect(archive.current?.name == "我的噜噜")
            #expect(archive.states == ["lulu": state])
        }
    }

    @Test func explicitCreationStartsFreshWithoutResettingTheOldCompanion() {
        let original = raisedState()
        var archive = PetCompanionArchive.migrate(states: ["lulu": original], selectedAppearanceID: "lulu", names: [:])
        archive.add(appearanceID: "lulu", name: "第二只", id: "synthetic-new")
        #expect(archive.selectedID == "synthetic-new")
        #expect(archive.states["synthetic-new"] == PetCareState())
        #expect(archive.states["lulu"] == original)
        archive.changeAppearance(to: "lumei")
        archive.select("lulu")
        #expect(archive.current?.appearanceID == "lulu")
        #expect(archive.states["lulu"] == original)
        archive.select("synthetic-new")
        #expect(archive.current?.appearanceID == "lumei")
        #expect(archive.states["synthetic-new"] == PetCareState())
    }

    @Test func migrationKeepsSeparateLegacyHistoriesAndNames() {
        var other = raisedState()
        other.xp = 120
        let histories = ["lulu": raisedState(), "jubao": other]
        let archive = PetCompanionArchive.migrate(states: histories, selectedAppearanceID: "jubao",
            names: ["lulu": "老朋友", "jubao": "橘宝名字"])
        #expect(archive.states == histories)
        #expect(archive.selectedID == "jubao")
        #expect(archive.companions.first { $0.id == "lulu" }?.name == "老朋友")
        #expect(archive.current?.name == "橘宝名字")
    }

    @Test func migrationRecoversRaisedIdentityFromAnUnfedSelectedSkin() {
        let histories = ["lulu": raisedState(), "jubao": PetCareState()]
        let archive = PetCompanionArchive.migrate(states: histories, selectedAppearanceID: "jubao", names: [:])
        #expect(archive.selectedID == "lulu")
        #expect(archive.current?.appearanceID == "jubao")
        #expect(archive.states == histories)
        #expect(archive.companions.count == 2)
    }

    @Test func cleanInstallAndUnknownSelectionsDoNotAccidentallyResetProgress() {
        var archive = PetCompanionArchive()
        archive.changeAppearance(to: "lulu")
        let id = archive.selectedID
        archive.select("not-a-companion")
        archive.changeAppearance(to: "")
        #expect(archive.selectedID == id)
        #expect(archive.current?.appearanceID == "lulu")
        #expect(archive.isValid)
    }

    @Test func projectAppearanceResolutionPrefersActiveThenExistingLegacyIdentity() {
        var archive = PetCompanionArchive.migrate(states: ["lulu": raisedState(), "jubao": PetCareState()],
                                                  selectedAppearanceID: "lulu", names: [:])
        archive.changeAppearance(to: "lumei")
        #expect(archive.companionID(forAppearance: "lumei") == "lulu")
        #expect(archive.companionID(forAppearance: "lulu") == "lulu")
        #expect(archive.companionID(forAppearance: "jubao") == "jubao")
        archive.add(appearanceID: "lumei", id: "synthetic-second")
        #expect(archive.companionID(forAppearance: "lumei") == "synthetic-second")
        #expect(archive.companionID(forAppearance: "missing") == nil)
    }

    @Test func archiveValidationRejectsAmbiguousOrOrphanedIdentity() {
        var archive = PetCompanionArchive()
        archive.add(appearanceID: "lulu", id: "test-id")
        archive.companions.append(archive.companions[0])
        #expect(!archive.isValid)
        archive.companions.removeLast()
        archive.states["orphan"] = PetCareState()
        #expect(!archive.isValid)
        archive.states.removeValue(forKey: "orphan")
        archive.version = 999
        #expect(!archive.isValid)
    }
}
