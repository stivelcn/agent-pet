import AppKit
import SwiftUI
import Testing
import AgentPetCore
@testable import agentpet

@MainActor
@Suite(.serialized)
struct PetPairInteractionTests {
    private func pack(_ id: String) throws -> ImagePetPack {
        try #require(SpriteSlicer.loadPack(directory: ImagePetStore.builtinDirectory.appendingPathComponent(id)))
    }
    private func visit(_ id: String = "hug", peer: String = "lumei", gesture: PetRelayGesture = .hug) -> PetRelayMessage {
        PetRelayMessage(id: id, clientID: id, pairID: "preview", senderName: "对方的主人", createdAt: 1,
                        gesture: gesture.rawValue, expiresAt: 31,
                        senderPet: PetRelayPetProfile(name: peer == "lumei" ? "噜妹" : "噜噜", builtinID: peer))
    }

    @Test func repeatedReplayRestartsAndOldCompletionsCannotInterruptQueuedVisits() throws {
        let player = PetPairInteractionPlayer()
        let first = visit("first"), second = visit("second", gesture: .poke)
        player.enqueue([first, second])
        let original = try #require(player.active?.id)
        #expect(player.active?.message.id == "first")
        #expect(player.pending.map(\.id) == ["second"])
        player.replay(first)
        let replay = try #require(player.active?.id)
        #expect(replay != original)
        player.finish(original)
        #expect(player.active?.id == replay)
        player.finish(replay)
        #expect(player.active?.message.id == "second")
        player.retain(["first"])
        #expect(player.active == nil)
        for _ in 0..<100 {
            player.replay(first)
            player.finish(try #require(player.active?.id))
            #expect(player.active == nil)
        }
        player.enqueue([first, second])
        player.stop()
        #expect(player.pending.isEmpty && player.active == nil)
    }

    @Test func bothBuiltinPetsHaveContactPosesAndImportedPetsKeepTheirOwnPixels() throws {
        for id in ["lulu", "lumei"] {
            let builtin = try pack(id)
            let poses = try #require(PetPairPoseLibrary.load(builtin))
            #expect(poses.count == 4 && poses.allSatisfy { $0.count == 6 })
            for row in poses {
                for frame in row {
                    #expect(frame.size == NSSize(width: 256, height: 256))
                    let cg = try #require(frame.cgImage(forProposedRect: nil, context: nil, hints: nil))
                    #expect(cg.alphaInfo == .last || cg.alphaInfo == .premultipliedLast)
                }
            }
        }
        var imported = try pack("lulu")
        imported = ImagePetPack(id: "custom", displayName: "自定义宠物", description: nil,
            clips: imported.clips, directory: URL(fileURLWithPath: "/不存在的素材目录"))
        let actual = try #require(PetPairArtwork(local: imported, message: visit()))
        #expect(actual.localIdle === imported.restingFrames.first)
        #expect(actual.localPoses.isEmpty)
        #expect(actual.visitorPoses.count == 6)
        let portrait = try #require(PetRelayAppearance.thumbnail(imported.restingFrames.first))
        var customVisitor = visit()
        customVisitor.senderPet = PetRelayPetProfile(name: "自定义访客", thumbnailPNG: portrait)
        let artwork = try #require(PetPairArtwork(local: imported, message: customVisitor))
        #expect(artwork.visitorIdle.size == NSSize(width: 96, height: 104))
        #expect(artwork.visitorPoses.isEmpty)
    }

    @Test func sceneFinishesExactlyOnceAndTeardownCancelsTimers() async throws {
        let stage = PetPairStageNSView(frame: NSRect(x: 0, y: 0, width: 408, height: 120))
        let artwork = try #require(PetPairArtwork(local: pack("lulu"), message: visit()))
        var completions = 0
        stage.configure(artwork: artwork, gesture: .hug, playbackID: UUID(), petSize: 120,
                        onCompletion: { _ in completions += 1 })
        for _ in 0..<220 where completions == 0 { try await Task.sleep(for: .milliseconds(20)) }
        #expect(completions == 1)
        #expect(!stage.isAnimating)
        try await Task.sleep(for: .milliseconds(100))
        #expect(completions == 1)
        stage.configure(artwork: artwork, gesture: .poke, playbackID: UUID(), petSize: 120,
                        onCompletion: { _ in completions += 1 })
        stage.teardown()
        try await Task.sleep(for: .milliseconds(100))
        #expect(!stage.isAnimating && completions == 1)
    }

    @Test func chineseBubblesUsePetNicknamesAndStayBoundedWithManyMessages() throws {
        try withChineseSnapshot {
            #expect(visit().interactionBubbleText == "噜妹抱了你一下")
            #expect(visit(gesture: .poke).interactionBubbleText == "噜妹戳了你一下")
            #expect(visit(peer: "lulu", gesture: .peek).interactionBubbleText == "噜噜探头看了看你")
            var fallback = visit()
            fallback.senderPet?.name = "  "
            #expect(fallback.interactionBubbleText == "对方的主人抱了你一下")
            _ = NSApplication.shared
            for (gesture, count) in PetRelayGesture.allCases.flatMap({ gesture in [1, 200].map { (gesture, $0) } }) {
                let messages = (0..<count).map { visit("\($0)", gesture: gesture) }
                let host = NSHostingView(rootView: PetInteractionBubbles(messages: messages,
                    replay: { _ in }, close: { _ in }).preferredColorScheme(.dark))
                let size = host.fittingSize
                #expect(size.width == 270 && size.height <= 144)
                host.frame = NSRect(origin: .zero, size: size)
                let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
                window.contentView = host
                host.layoutSubtreeIfNeeded()
                if count == 1, let root = ProcessInfo.processInfo.environment["AGENTPET_UI_SNAPSHOT_DIR"] {
                    let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
                    host.cacheDisplay(in: host.bounds, to: bitmap)
                    let folder = URL(fileURLWithPath: root)
                    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                    try #require(bitmap.representation(using: .png, properties: [:]))
                        .write(to: folder.appendingPathComponent("replay-bubble-\(gesture.rawValue).png"))
                }
                window.contentView = nil
            }
        }
    }

    @Test func liveSceneRendersBothDirectionsAndExportsActualPlaybackFramesOffscreen() throws {
        for local in ["lulu", "lumei"] {
            let peer = local == "lulu" ? "lumei" : "lulu"
            for gesture in PetRelayGesture.allCases {
                let art = try #require(PetPairArtwork(local: pack(local), message: visit(peer: peer, gesture: gesture)))
                for onRight in [false, true] {
                    let stage = PetPairStageNSView(frame: NSRect(x: 0, y: 0, width: 510, height: 150))
                    stage.configure(artwork: art, gesture: gesture, playbackID: UUID(), petSize: 150,
                                    visitorOnRight: onRight, animate: false, onCompletion: { _ in })
                    let contact = try #require(stage.snapshot(at: 1.7))
                    #expect(contact.pixelsWide == 1020 && contact.pixelsHigh == 300)
                    #expect(!stage.isAnimating)
                    if let root = ProcessInfo.processInfo.environment["AGENTPET_UI_SNAPSHOT_DIR"] {
                        let folder = URL(fileURLWithPath: root)
                            .appendingPathComponent("\(local)-\(gesture.rawValue)-\(onRight ? "right" : "left")")
                        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                        for i in 0...36 {
                            let bitmap = try #require(stage.snapshot(at: Double(i) / 10))
                            try #require(bitmap.representation(using: .png, properties: [:]))
                                .write(to: folder.appendingPathComponent(String(format: "%02d.png", i)))
                        }
                    }
                    stage.teardown()
                }
            }
        }
    }
}
