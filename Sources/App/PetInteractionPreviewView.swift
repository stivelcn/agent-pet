import SwiftUI

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
    @StateObject private var player = PetInteractionPlayer()
    @State private var packs: [ImagePetPack] = []
    @State private var selectedID = "lulu"

    init(packs: [ImagePetPack] = []) {
        _packs = State(initialValue: packs)
    }

    private var pack: ImagePetPack? { packs.first { $0.id == selectedID } }
    private var canAnimate: Bool { pet.animationsEnabled && !reduceMotion }

    var body: some View {
        VStack(spacing: 18) {
            HStack {
                Label(InterfaceText.format("Interaction preview"), systemImage: "sparkles").font(.headline)
                Spacer()
                Button(InterfaceText.format("Done")) { dismiss() }.keyboardShortcut(.cancelAction)
            }
            Picker(InterfaceText.format("Pet"), selection: $selectedID) {
                ForEach(packs) { pack in Text(verbatim: pack.displayName).tag(pack.id) }
            }
            .pickerStyle(.segmented)
            .onChange(of: selectedID) { _, _ in player.stop() }

            ZStack {
                RoundedRectangle(cornerRadius: 18).fill(.quaternary)
                if let pack {
                    VStack(spacing: 8) {
                        PetInteractionSpriteView(pack: pack, player: player, size: 190)
                            .environment(\.animationsEnabled, pet.animationsEnabled)
                        Text(InterfaceText.format(player.action?.label ?? "Idle"))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                } else {
                    Text(InterfaceText.format("Interaction artwork is unavailable.")).foregroundStyle(.secondary)
                }
            }
            .frame(height: 240)

            HStack(spacing: 8) {
                ForEach(PetInteraction.allCases) { action in
                    Button {
                        if let pack { player.play(action, in: pack, animationsEnabled: canAnimate) }
                    } label: {
                        Label(InterfaceText.format(action.label), systemImage: action.symbol)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(!canAnimate || pack?.interactionClips[action] == nil)
                    .accessibilityIdentifier("pet-interaction-\(action.rawValue)")
                }
            }
            Text(InterfaceText.format(canAnimate
                 ? "Preview locally. Each action plays once, then returns to idle."
                 : "Turn on animations and turn off Reduce Motion to preview actions."))
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(22)
        .frame(width: 540)
        .onAppear {
            guard packs.isEmpty else { return }
            packs = ["lulu", "lumei"].compactMap {
                SpriteSlicer.loadPack(directory: ImagePetStore.builtinDirectory.appendingPathComponent($0))
            }
        }
        .onDisappear { player.stop() }
    }
}
