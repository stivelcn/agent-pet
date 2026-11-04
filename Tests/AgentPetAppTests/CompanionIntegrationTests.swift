import AppKit
import Foundation
import Testing
import AgentPetCore
@testable import agentpet

@MainActor
@Suite(.serialized)
struct CompanionIntegrationTests {
    private func withDefaults(_ test: (UserDefaults) throws -> Void) throws {
        let suite = "local.agentpet.tests.companions.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        try test(defaults)
    }

    @Test func migrationAndRestartPreserveLegacyBytesAndFullCareHistory() throws {
        try withDefaults { defaults in
            var original = PetCareState()
            // Explicit isolated synthetic fixture, not the user's real history.
            original.xp = 3560
            original.tokenCarry = 314
            original.totalTokens = 10_000
            original.totalMeals = 8
            original.streakDays = 5
            original.days = ["2026-11-04": 10_000]
            original.unlockedAchievements = [.firstMeal, .level5]
            let legacy = try JSONEncoder().encode(["lulu": original])
            defaults.set(legacy, forKey: "agentpet.care.v2")
            defaults.set("lulu", forKey: "agentpet.selectedPetID")
            defaults.set(["lulu": "老朋友"], forKey: "agentpet.petNames")
            let care = PetCareController(defaults: defaults, notify: false)
            care.changeAppearance(to: "lumei")
            #expect(care.current == original)
            #expect(care.currentPetID == "lulu")
            #expect(care.state(for: "lumei") == original)
            let reloaded = PetCareController(defaults: defaults, notify: false)
            #expect(reloaded.currentAppearanceID == "lumei")
            #expect(reloaded.current == original)
            #expect(reloaded.archive.current?.name == "老朋友")
            #expect(defaults.data(forKey: "agentpet.care.v2") == legacy)
            // Once migrated, the archive is authoritative even if an older app
            // leaves an unexpected type in a retired preference.
            defaults.set("retired synthetic preference", forKey: "agentpet.care.v2")
            let authoritative = PetCareController(defaults: defaults, notify: false)
            #expect(authoritative.current == original)
            #expect(authoritative.persistenceError == nil)
        }
    }

    @Test func newCompanionAndFeedingRouteToIdentityInsteadOfAppearance() throws {
        ImagePetStore.shared.reload()
        try withDefaults { defaults in
            defaults.set("lulu", forKey: "agentpet.selectedPetID")
            let care = PetCareController(defaults: defaults, notify: false)
            care.feedTokens(50_000)
            care.recordMeal()
            let oldID = try #require(care.currentPetID)
            let old = care.current
            care.changeAppearance(to: "lumei")
            care.feedTokens(15_000, petID: "lumei")
            #expect(care.current.totalTokens == old.totalTokens + 15_000)
            #expect(care.currentPetID == oldID)
            let raised = care.current
            let newID = try #require(care.createCompanion(appearanceID: "lumei", name: "新的伙伴"))
            #expect(newID != oldID)
            #expect(care.current == PetCareState())
            care.recordMeal(petID: "lumei")
            care.feedTokens(5_000, petID: "lumei")
            #expect(care.current.totalMeals == 1)
            #expect(care.current.totalTokens == 5_000)
            #expect(care.state(forCompanionID: oldID) == raised)
            care.selectCompanion(oldID)
            #expect(care.current == raised)
            let reloaded = PetCareController(defaults: defaults, notify: false)
            #expect(reloaded.currentPetID == oldID)
            #expect(reloaded.state(forCompanionID: newID).totalMeals == 1)
            #expect(reloaded.archive == care.archive)
        }
    }

    @Test func companionRenameSurvivesSkinSwitchAndClearingIsSupported() throws {
        try withDefaults { defaults in
            let care = PetCareController(defaults: defaults, notify: false)
            care.changeAppearance(to: "lulu")
            care.renameCurrent(to: "  我的小伙伴  ")
            care.changeAppearance(to: "lumei")
            #expect(care.archive.current?.name == "我的小伙伴")
            care.renameCurrent(to: "  ")
            #expect(care.archive.current?.name == nil)
        }
    }

    @Test func unreadableArchiveIsNeverOverwrittenBySelectionOrFeeding() throws {
        try withDefaults { defaults in
            let original = Data("unreadable fixture".utf8)
            defaults.set(original, forKey: PetCareController.archiveKey)
            let care = PetCareController(defaults: defaults, notify: false)
            #expect(care.persistenceError != nil)
            care.changeAppearance(to: "lulu")
            care.feedTokens(50_000)
            #expect(care.createCompanion(appearanceID: "lumei", name: "test") == nil)
            #expect(defaults.data(forKey: PetCareController.archiveKey) == original)
            defaults.set("wrong-type synthetic fixture", forKey: PetCareController.archiveKey)
            let wrongType = PetCareController(defaults: defaults, notify: false)
            #expect(wrongType.persistenceError != nil)
            wrongType.changeAppearance(to: "lulu")
            #expect(defaults.string(forKey: PetCareController.archiveKey) == "wrong-type synthetic fixture")
        }
    }

    @Test func legacyV1IsRetainedAndUnreadableV2CannotBeReplaced() throws {
        try withDefaults { defaults in
            var state = PetCareState()
            state.xp = 500
            let data = try JSONEncoder().encode(state)
            defaults.set(data, forKey: "agentpet.care.v1")
            let migrated = PetCareController(defaults: defaults, notify: false)
            #expect(migrated.current == state)
            #expect(defaults.data(forKey: "agentpet.care.v1") == data)
            defaults.removeObject(forKey: PetCareController.archiveKey)
            let invalid = Data("invalid v2 fixture".utf8)
            defaults.set(invalid, forKey: "agentpet.care.v2")
            let blocked = PetCareController(defaults: defaults, notify: false)
            #expect(blocked.persistenceError != nil)
            blocked.refreshDay()
            #expect(defaults.data(forKey: PetCareController.archiveKey) == nil)
            #expect(defaults.data(forKey: "agentpet.care.v2") == invalid)
        }
    }

    @Test func bundledAppearancesLoadInStableOrderAndCannotBeDeleted() throws {
        let store = ImagePetStore.shared
        store.reload()
        #expect(Array(store.packs.prefix(2).map(\.id)) == ["lulu", "lumei"])
        #expect(store.packs.filter { $0.id == "lulu" }.count == 1)
        for id in ["lulu", "lumei"] {
            let pack = try #require(store.pack(id: id))
            #expect(pack.isBuiltin)
            #expect(!pack.restingFrames.isEmpty)
            store.delete(pack)
            #expect(store.pack(id: id) != nil)
            #expect(FileManager.default.fileExists(atPath: pack.directory.path))
        }
    }

    @Test func lumeiUsesSixFixedTransparentCellsWithAuthoredTiming() throws {
        let pack = try #require(SpriteSlicer.loadPack(directory: ImagePetStore.builtinDirectory.appendingPathComponent("lumei")))
        #expect(pack.displayName == "噜妹")
        #expect(pack.clipCount == 1)
        #expect(pack.restingFrames.count == 6)
        #expect(pack.restingFrameDurations == [1.3, 0.36, 0.09, 0.11, 0.16, 1.18])
        for frame in pack.restingFrames {
            #expect(frame.size == NSSize(width: 192, height: 208))
            let cg = try #require(frame.cgImage(forProposedRect: nil, context: nil, hints: nil))
            #expect(cg.width == 192 && cg.height == 208)
            let bitmap = NSBitmapImageRep(cgImage: cg)
            #expect(bitmap.colorAt(x: 0, y: 0)?.alphaComponent == 0)
            #expect(bitmap.colorAt(x: 191, y: 207)?.alphaComponent == 0)
        }
        let view = SpriteLayerNSView()
        defer { view.teardown() }
        view.configure(frames: pack.restingFrames, fps: 2, frameDurations: pack.restingFrameDurations)
        #expect(abs((0..<6).map { view.frameDuration(at: $0) }.reduce(0, +) - 3.2) < 0.0001)
        view.configure(frames: pack.restingFrames, fps: 1, frameDurations: pack.restingFrameDurations)
        #expect(view.frameDuration(at: 0) == 2.6)
        #expect(view.frameDuration(at: 2) == 0.18)
    }

    @Test func validLocalBuiltinWinsWithoutDuplicatesAndBrokenLocalFallsBack() throws {
        #expect(AgentPetPaths.baseDir.contains(".test-state."))
        let store = ImagePetStore.shared
        let folder = URL(fileURLWithPath: AgentPetPaths.baseDir)
            .appendingPathComponent("pets/synthetic-lulu-override-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: folder)
            store.reload()
        }
        let source = ImagePetStore.builtinDirectory.appendingPathComponent("lulu")
        for file in ["pet.json", "spritesheet.webp"] {
            try FileManager.default.copyItem(at: source.appendingPathComponent(file), to: folder.appendingPathComponent(file))
        }
        store.reload()
        #expect(store.pack(id: "lulu")?.directory.path == folder.path)
        #expect(store.packs.filter { $0.id == "lulu" }.count == 1)
        try FileManager.default.removeItem(at: folder.appendingPathComponent("spritesheet.webp"))
        store.reload()
        #expect(store.pack(id: "lulu")?.directory.path == source.path)
        #expect(store.loadFailures["lulu"] == nil)
    }

    @Test func fastLoadingIncludesBothBuiltinsAndSurvivesAnImmediateReload() async throws {
        let store = ImagePetStore.shared
        store.loadFast(priorityID: "lumei")
        #expect(store.pack(id: "lumei") != nil)
        for _ in 0..<300 where store.isLoading {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(!store.isLoading)
        #expect(Array(store.packs.prefix(2).map(\.id)) == ["lulu", "lumei"])
        store.loadFast(priorityID: "lulu")
        store.reload()
        try await Task.sleep(for: .milliseconds(150))
        #expect(store.packs.filter { $0.id == "lulu" }.count == 1)
        #expect(store.pack(id: "lumei") != nil)
    }
    @Test func petControllerAppearanceSelectionPreservesTheActiveCompanion() throws {
        #expect(AgentPetPaths.baseDir.contains(".test-state."))
        ImagePetStore.shared.reload()
        let pet = PetController.shared
        let original = pet.selectedPetID
        defer { pet.selectedPetID = original }
        pet.selectedPetID = "lulu"
        let care = PetCareController.shared
        // Isolated synthetic feeding through the real application entry point.
        care.feedTokens(1)
        let state = care.current
        let id = care.currentPetID
        for appearance in ["lumei", "lulu"] {
            pet.selectedPetID = appearance
            #expect(care.currentAppearanceID == appearance)
            #expect(care.currentPetID == id)
            #expect(care.current == state)
            #expect(care.state(for: appearance) == state)
        }
    }

}
