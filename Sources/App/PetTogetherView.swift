import AppKit
import SwiftUI
import AgentPetCore

/// Shared by the right-click card, composer and desktop invitation bubble.
struct PetTogetherControls: View {
    @ObservedObject var relay: PetRelayController = .shared
    var showInvites = true
    var compact = false

    @ViewBuilder var body: some View {
        if compact { content.buttonStyle(PetMenuButtonStyle()) }
        else { content.buttonStyle(.bordered).controlSize(.small) }
    }

    private var content: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let now = context.date.timeIntervalSince1970 + relay.serverOffset
            VStack(alignment: .leading, spacing: 7) {
                if let pending = relay.mailbox.pendingTogether {
                    Text(InterfaceText.format(pending.stopsPresentation
                        ? "Already home here. Reconnecting to tell your friend…"
                        : "Invitation saved. Waiting for the connection…"))
                        .font(.caption).fixedSize(horizontal: false, vertical: true)
                    if !pending.stopsPresentation {
                        Button(InterfaceText.format("Cancel invitation")) { Task { await relay.cancelTogetherRetry() } }
                    }
                } else if let session = relay.togetherSession, session.isPending(at: now) {
                    let own = session.initiatorID == relay.mailbox.deviceID
                    Text(InterfaceText.format(own ? "Waiting for your friend to accept…"
                        : session.mode == .visit ? "%@ wants to visit for 5 minutes" : "%@ invites you to work together",
                        relay.pair?.peerPet?.name ?? relay.pair?.peerName ?? ""))
                        .font(.caption).fixedSize(horizontal: false, vertical: true)
                    HStack {
                        if own { action("Cancel invitation", "cancel") }
                        else {
                            action(session.mode == .visit ? "Come on over" : "Let's work together", "accept")
                            action("Maybe later", "decline")
                        }
                    }
                } else if let session = relay.togetherSession, session.isActive(at: now) {
                    Text(InterfaceText.format(session.mode == .visit
                        ? (session.isAway(deviceID: relay.mailbox.deviceID, at: now) ? "Visiting your friend's home" : "Your friend is visiting")
                        : session.isResting(at: now) ? "Tea break together" : "Working together"))
                        .font(.caption.bold())
                    let target = session.mode == .work && !session.isResting(at: now) ? session.restAt ?? session.expiresAt : session.expiresAt
                    let seconds = max(0, Int(ceil(target - now)))
                    Text(verbatim: String(format: "%02d:%02d", seconds / 60, seconds % 60))
                        .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    HStack {
                        if session.mode == .work && !session.isResting(at: now) { action("Take a tea break together", "rest") }
                        action(session.mode == .work ? "Finish working together"
                            : session.isAway(deviceID: relay.mailbox.deviceID, at: now) ? "Call them home" : "Send them home", "end")
                    }
                } else if showInvites && relay.pair != nil {
                    HStack {
                        Button(InterfaceText.format("Go visiting")) { Task { await relay.inviteTogether(.visit) } }
                        Button(InterfaceText.format("Work together")) { Task { await relay.inviteTogether(.work) } }
                    }
                    .disabled(!relay.supportsTogether)
                    if !relay.supportsTogether {
                        Text(InterfaceText.format("Visits and working together need both friends to update LuMate."))
                            .font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                }
                if let error = relay.persistenceError ?? relay.error {
                    Text(verbatim: error).font(.caption2).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
                }
            }
            .disabled(relay.isBusy)
        }
        .accessibilityIdentifier("pet-together-controls")
    }

    private func action(_ title: String, _ value: String) -> some View {
        Button(InterfaceText.format(title)) { Task { await relay.actTogether(value) } }
            .accessibilityIdentifier("pet-together-" + value)
    }
}

struct PetTogetherBubble: View {
    @ObservedObject var relay: PetRelayController = .shared
    var body: some View {
        PetTogetherControls(relay: relay, showInvites: false)
            .padding(10).frame(width: 270, alignment: .leading)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.teal.opacity(0.4)))
    }
}

/// The travelling pet leaves an actual clickable home; its right-click card owns the recall action.
struct PetAwayNestView: View {
    var size: CGFloat
    var body: some View {
        VStack(spacing: 3) {
            Image(systemName: "house.fill").font(.system(size: size * 0.45))
                .foregroundStyle(Color.brown.gradient)
                .overlay(alignment: .topTrailing) {
                    Image(systemName: "pawprint.fill").font(.system(size: size * 0.16)).foregroundStyle(.orange)
                }
            Text(InterfaceText.format("Gone to a friend's home"))
                .font(.system(size: 10)).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(width: size, height: size).contentShape(Rectangle())
        .accessibilityIdentifier("pet-away-nest")
    }
}

/// Long-lived company uses the pets' real idle loops; only the short high-five runs at 30fps.
struct PetTogetherSceneView: View {
    let local: ImagePetPack
    let peer: PetRelayPetProfile?
    var petSize: CGFloat
    var localOffset: CGFloat = 0
    var visitorOnRight = false
    var resting = false
    var finishing = false
    @Environment(\.animationsEnabled) private var animationsEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var start = Date()

    private var peerPack: ImagePetPack? { PetRelayAppearance.pack(for: peer) }
    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: !finishing || !animationsEnabled || reduceMotion)) { context in
            let elapsed = min(2.4, max(0, context.date.timeIntervalSince(start)))
            let contact = finishing ? max(0, 1 - abs(elapsed - 1.0) / 0.7) : 0
            let direction: CGFloat = visitorOnRight ? 1 : -1
            let home = petSize * 1.7 + localOffset
            ZStack(alignment: .topLeading) {
                sprite(local, profile: nil, pose: finishing ? 2 : nil)
                    .scaleEffect(x: finishing ? direction : 1, y: 1)
                    .rotationEffect(.degrees(finishing ? -direction * 8 * contact : 0))
                    .position(x: home + direction * petSize * 0.08 * contact, y: petSize / 2)
                sprite(peerPack, profile: peer, pose: finishing ? 2 : nil)
                    .scaleEffect(x: finishing ? -direction : 1, y: 1)
                    .rotationEffect(.degrees(finishing ? direction * 8 * contact : 0))
                    .position(x: home + direction * petSize * (0.88 - 0.28 * contact), y: petSize / 2)
                if resting {
                    Text(verbatim: "☕").font(.system(size: petSize * 0.2))
                        .position(x: home, y: petSize * 0.87)
                    Text(verbatim: "☕").font(.system(size: petSize * 0.2))
                        .position(x: home + direction * petSize * 0.88, y: petSize * 0.87)
                }
                if finishing {
                    Image(systemName: "sparkles").foregroundStyle(.yellow)
                        .font(.system(size: petSize * 0.22))
                        .opacity(contact).position(x: home + direction * petSize * 0.35, y: petSize * 0.3)
                }
            }
            .frame(width: petSize * 3.4, height: petSize)
        }
        .contentShape(Rectangle())
        .accessibilityLabel(InterfaceText.format(finishing ? "High five! Well done today." : resting ? "Tea break together" : "Working together"))
    }

    @ViewBuilder private func sprite(_ pack: ImagePetPack?, profile: PetRelayPetProfile?, pose: Int?) -> some View {
        if let pack {
            let poses = pose.flatMap { PetPairPoseLibrary.load(pack)?[$0] }
            ImageSpriteView(frames: poses.map { [$0[3]] } ?? pack.restingFrames,
                            fps: resting ? 1 : 2, size: petSize,
                            frameDurations: poses == nil ? pack.restingFrameDurations : nil)
        } else { PetRelayAvatar(profile: profile, size: petSize) }
    }
}
