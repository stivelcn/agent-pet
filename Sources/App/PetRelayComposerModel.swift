import Foundation
import Combine
import AgentPetCore

/// Ephemeral UI only: opening, cancelling or dismissing a composer never handles its message.
/// A composer is bound to the pairing it opened for, even if an awaited sync changes partners.
@MainActor
final class PetRelayComposerModel: ObservableObject {
    let relay: PetRelayController
    let pairID: String?
    let peerName: String?
    let replyTo: PetRelayMessage?
    @Published var text = ""
    @Published private(set) var submitting = false
    @Published private(set) var queuedDraftID: String?
    @Published private(set) var accepted = false

    init(relay: PetRelayController, replyTo: PetRelayMessage? = nil) {
        self.relay = relay
        pairID = relay.pair?.id
        peerName = relay.pair?.peerName
        self.replyTo = replyTo
    }

    var validContext: Bool {
        guard let pairID, relay.pair?.id == pairID else { return false }
        guard let replyTo else { return true }
        return replyTo.pairID == pairID && relay.incoming.contains { $0.id == replyTo.id }
    }
    var waitingForRetry: Bool {
        guard let queuedDraftID else { return false }
        return relay.mailbox.outbox.contains { $0.id == queuedDraftID }
    }
    var didSend: Bool {
        accepted || (queuedDraftID.map { id in relay.mailbox.sent.contains { $0.clientID == id } } ?? false)
    }
    var canSend: Bool {
        validContext && !submitting && !relay.isBusy && !waitingForRetry && !didSend
    }
    var canSendText: Bool { canSend && PetRelayValidation.validText(text) }

    @discardableResult
    func sendText() async -> Bool {
        guard canSendText else { return false }
        return await submit(text: text)
    }
    @discardableResult
    func sendIcon(_ icon: PetRelayIcon) async -> Bool {
        guard canSend else { return false }
        return await submit(icon: icon)
    }
    func sendGesture(_ gesture: PetRelayGesture) async -> Bool {
        guard canSend, relay.supportsInteractions else { return false }
        return await submit(gesture: gesture)
    }
    private func submit(text: String? = nil, icon: PetRelayIcon? = nil, gesture: PetRelayGesture? = nil) async -> Bool {
        submitting = true
        defer { submitting = false }
        queuedDraftID = nil
        let before = Set(relay.mailbox.outbox.map(\.id))
        let sent = await relay.send(text: text, icon: icon, replyTo: replyTo?.id, expectedPairID: pairID, gesture: gesture)
        if sent {
            accepted = true
            self.text = ""
        } else if let draft = relay.mailbox.outbox.first(where: { !before.contains($0.id) }) {
            queuedDraftID = draft.id
            self.text = ""
        }
        return sent
    }

    /// Cancelling an automatic retry only removes that outgoing draft, never the received message.
    func cancelRetry() {
        guard !submitting, !relay.isBusy, let id = queuedDraftID,
              let draft = relay.mailbox.outbox.first(where: { $0.id == id }) else { return }
        relay.discardDraft(id)
        if !relay.mailbox.outbox.contains(where: { $0.id == id }) {
            text = draft.text ?? ""
            queuedDraftID = nil
        }
    }
}
