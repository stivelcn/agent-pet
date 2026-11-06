import SwiftUI
import AgentPetCore

/// Reusable one-shot sprite; it always returns to the pack's unchanged idle clip.
struct PetInteractionSpriteView: View {
    let pack: ImagePetPack
    @ObservedObject var player: PetInteractionPlayer
    var size: CGFloat = 160
    var idleFPS: Double = 2
    @Environment(\.animationsEnabled) private var animationsEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var clip: PetInteractionClip? {
        guard animationsEnabled, !reduceMotion, let action = player.action else { return nil }
        return pack.interactionClips[action]
    }

    var body: some View {
        let id = player.playbackID
        ImageSpriteView(frames: clip?.frames ?? pack.restingFrames,
                        fps: clip == nil ? idleFPS : 2, size: size,
                        frameDurations: clip?.frameDurations ?? pack.restingFrameDurations,
                        loops: clip == nil, onCompletion: { player.finish(id) }, playbackID: id)
            .onChange(of: animationsEnabled) { _, enabled in if !enabled { player.stop() } }
            .onChange(of: reduceMotion) { _, reduced in if reduced { player.stop() } }
            .onChange(of: pack.id) { _, _ in player.stop() }
            .onDisappear { player.stop() }
    }
}

/// Local preview only: never sends a message, registers a device or changes a pet.
struct PetInteractionPreviewView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject private var pet = PetController.shared
    @StateObject private var player = PetPairInteractionPlayer()
    @State private var packs: [ImagePetPack] = []
    @State private var selectedID = "lulu"
    @State private var retained: PetRelayMessage?

    init(packs: [ImagePetPack] = []) { _packs = State(initialValue: packs) }
    private var pack: ImagePetPack? { packs.first { $0.id == selectedID } }
    private var peer: ImagePetPack? { packs.first { $0.id != selectedID } }
    private var canAnimate: Bool { pet.animationsEnabled && !reduceMotion }

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Label(InterfaceText.format("Interaction preview"), systemImage: "sparkles").font(.headline)
                Spacer()
                Button(InterfaceText.format("Done")) { dismiss() }.keyboardShortcut(.cancelAction)
            }
            Picker(InterfaceText.format("Your pet"), selection: $selectedID) {
                ForEach(packs) { pack in Text(verbatim: pack.id == "lulu" ? "噜噜" : pack.displayName).tag(pack.id) }
            }
            .pickerStyle(.segmented)
            .onChange(of: selectedID) { _, _ in player.stop(); retained = nil }

            VStack(spacing: 4) {
                if let retained {
                    PetInteractionBubbles(messages: [retained], canReplay: canAnimate,
                        replay: { player.replay($0) }, close: { _ in self.retained = nil; player.stop() })
                }
                if let pack {
                    if let active = player.active, let art = PetPairArtwork(local: pack, message: active.message) {
                        PetPairSceneView(artwork: art, playback: active, petSize: 140,
                            onCompletion: { player.finish($0) })
                            .frame(width: 476, height: 140)
                    } else {
                        ImageSpriteView(frames: pack.restingFrames, fps: 2, size: 140,
                                        frameDurations: pack.restingFrameDurations)
                    }
                    Text(verbatim: pack.id == "lulu" ? "噜噜" : pack.displayName).font(.caption).foregroundStyle(.secondary)
                } else {
                    Text(InterfaceText.format("Interaction artwork is unavailable.")).foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity).frame(height: 230)
            .background(RoundedRectangle(cornerRadius: 18).fill(.quaternary))

            HStack(spacing: 8) {
                ForEach(PetRelayGesture.allCases, id: \.rawValue) { action in
                    Button { simulate(action) } label: {
                        Text(InterfaceText.format(action.labelKey)).frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered).disabled(!canAnimate || peer == nil)
                    .accessibilityIdentifier("pet-interaction-\(action.rawValue)")
                }
            }
            Text(InterfaceText.format(canAnimate
                 ? "Receive a local preview. Replay the bubble as often as you like; close it to dismiss."
                 : "Turn on animations and turn off Reduce Motion to preview actions."))
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(22).frame(width: 540)
        .environment(\.animationsEnabled, pet.animationsEnabled)
        .onAppear {
            guard packs.isEmpty else { return }
            packs = ["lulu", "lumei"].compactMap {
                SpriteSlicer.loadPack(directory: ImagePetStore.builtinDirectory.appendingPathComponent($0))
            }
        }
        .onChange(of: canAnimate) { _, allowed in if !allowed { player.stop() } }
        .onDisappear { player.stop() }
    }

    private func simulate(_ gesture: PetRelayGesture) {
        guard canAnimate, let peer else { return }
        let message = PetRelayMessage(id: UUID().uuidString, clientID: "preview", pairID: "preview",
            senderName: peer.id == "lulu" ? "噜噜" : peer.displayName, createdAt: Date().timeIntervalSince1970,
            gesture: gesture.rawValue, senderPet: PetRelayPetProfile(name: peer.id == "lulu" ? "噜噜" : peer.displayName, builtinID: peer.id))
        retained = message
        player.replay(message)
    }
}
