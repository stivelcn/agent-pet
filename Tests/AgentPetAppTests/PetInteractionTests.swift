import AppKit
import SwiftUI
import Testing
import AgentPetCore
@testable import agentpet

@MainActor
@Suite(.serialized)
struct PetInteractionTests {
    private func builtin(_ id: String = "lulu") throws -> ImagePetPack {
        try #require(SpriteSlicer.loadPack(directory: ImagePetStore.builtinDirectory.appendingPathComponent(id)))
    }

    @Test func bothPetsHaveFourBoundedClipsAndKeepTheirOriginalIdle() throws {
        for id in ["lulu", "lumei"] {
            let pack = try builtin(id)
            #expect(Set(pack.interactionClips.keys) == Set(PetInteraction.allCases))
            #expect(!pack.restingFrames.isEmpty)
            for clip in pack.interactionClips.values {
                #expect(clip.frames.count == 6)
                #expect(clip.frameDurations.count == clip.frames.count)
                #expect(clip.duration >= 2 && clip.duration <= 4)
                #expect(clip.frames.allSatisfy { $0.size == NSSize(width: 192, height: 208) })
                #expect(!clip.frames.contains { action in pack.restingFrames.contains { $0 === action } })
            }
        }
    }

    @Test func missingAndMalformedSidecarsDoNotBreakIdlePacks() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        #expect(PetInteractionLibrary.load(directory: directory).isEmpty)
        try Data("bad json".utf8).write(to: directory.appendingPathComponent("interactions.json"))
        #expect(PetInteractionLibrary.load(directory: directory).isEmpty)
        let source = try builtin().directory
        try FileManager.default.copyItem(at: source.appendingPathComponent("interactions.png"),
                                         to: directory.appendingPathComponent("interactions.png"))
        var manifest = try #require(JSONSerialization.jsonObject(with:
            Data(contentsOf: source.appendingPathComponent("interactions.json"))) as? [String: Any])
        manifest["spritesheetPath"] = "../interactions.png"
        try JSONSerialization.data(withJSONObject: manifest).write(to: directory.appendingPathComponent("interactions.json"))
        #expect(PetInteractionLibrary.load(directory: directory).isEmpty)
        manifest["spritesheetPath"] = "interactions.png"
        manifest["clips"] = ["poke": ["row": -1, "frameDurationsMS": [100, 100]],
                             "hug": ["row": 0, "frameDurationsMS": [3_000, 3_000]]]
        try JSONSerialization.data(withJSONObject: manifest).write(to: directory.appendingPathComponent("interactions.json"))
        #expect(PetInteractionLibrary.load(directory: directory).isEmpty)
    }

    @Test func staleCompletionsCannotStopNewActionsAndDisabledMotionStaysIdle() throws {
        let pack = try builtin()
        let player = PetInteractionPlayer()
        #expect(player.play(.poke, in: pack))
        let previous = player.playbackID
        #expect(player.play(.hug, in: pack))
        player.finish(previous)
        #expect(player.action == .hug)
        player.finish(player.playbackID)
        #expect(player.action == nil)
        #expect(!player.play(.peek, in: pack, animationsEnabled: false))
        #expect(!player.play(.peek, in: pack, reduceMotion: true))
        var oldPack = pack
        oldPack.interactionClips = [:]
        #expect(!player.play(.poke, in: oldPack))
        #expect(player.action == nil)
    }

    @Test func oneShotCompletesOnceAndCanRestartWithANewIdentity() async throws {
        let clip = try #require(builtin().interactionClips[.poke])
        let view = SpriteLayerNSView()
        var completions = 0
        let timings = Array(repeating: 0.02, count: clip.frames.count)
        func play(_ id: UUID) {
            view.configure(frames: clip.frames, fps: 2, frameDurations: timings, loops: false,
                           onCompletion: { completions += 1 }, playbackID: id)
        }
        play(UUID())
        for _ in 0..<100 where completions < 1 { try await Task.sleep(for: .milliseconds(20)) }
        #expect(completions == 1)
        try await Task.sleep(for: .milliseconds(200))
        #expect(completions == 1)
        play(UUID())
        for _ in 0..<100 where completions < 2 { try await Task.sleep(for: .milliseconds(20)) }
        #expect(completions == 2)
        view.teardown()
    }

    @Test func tearingDownAnActionCancelsItsCompletion() async throws {
        let clip = try #require(builtin().interactionClips[.poke])
        let view = SpriteLayerNSView()
        var completed = false
        view.configure(frames: clip.frames, fps: 2,
                       frameDurations: Array(repeating: 0.02, count: clip.frames.count),
                       loops: false, onCompletion: { completed = true })
        view.teardown()
        try await Task.sleep(for: .milliseconds(240))
        #expect(!completed)
    }

    @Test func previewRendersBothPetsWithoutChangingTheSelectedAppearance() throws {
        try withChineseSnapshot {
            _ = NSApplication.shared
            _ = AppLanguage.shared
            let selected = PetController.shared.selectedPetID
            let packs = try [builtin("lulu"), builtin("lumei")]
            let view = PetInteractionPreviewView(packs: packs).preferredColorScheme(.dark)
            let host = NSHostingView(rootView: view)
            let size = host.fittingSize
            #expect(size.width == 540)
            #expect(size.height > 300 && size.height < 600)
            host.frame = NSRect(origin: .zero, size: size)
            let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
            window.contentView = host
            host.layoutSubtreeIfNeeded()
            let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: bitmap)
            if let directory = ProcessInfo.processInfo.environment["AGENTPET_UI_SNAPSHOT_DIR"] {
                let url = URL(fileURLWithPath: directory)
                try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
                try #require(bitmap.representation(using: .png, properties: [:]))
                    .write(to: url.appendingPathComponent("interaction-preview.png"))
            }
            window.contentView = nil
            #expect(PetController.shared.selectedPetID == selected)
        }
    }

    @Test func remotePortraitsUseBoundedPNGAndShippedBuiltinInsteadOfLocalOverrides() throws {
        let pack = try builtin("lumei")
        let encoded = try #require(PetRelayAppearance.thumbnail(pack.restingFrames.first))
        #expect(encoded.utf8.count <= 43_692)
        let profile = PetRelayPetProfile(name: "custom", thumbnailPNG: encoded)
        let portrait = try #require(PetRelayAppearance.portrait(for: profile))
        #expect(portrait.size == NSSize(width: 96, height: 104))
        #expect(PetRelayAppearance.portrait(for: PetRelayPetProfile(name: "bad", thumbnailPNG: "not-png")) == nil)
        #expect(PetRelayAppearance.pack(for: PetRelayPetProfile(name: "unknown", builtinID: "../lulu")) == nil)
        let remote = try #require(PetRelayAppearance.pack(for: PetRelayPetProfile(name: "friend", builtinID: "lulu")))
        #expect(remote.directory == ImagePetStore.builtinDirectory.appendingPathComponent("lulu"))
        #expect(remote.interactionClips.count == 4)
    }
}
