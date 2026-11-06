import AppKit
import SwiftUI
import AgentPetCore

/// Settings manage the pairing only. Sending and replying live beside the pet.
struct PetRelaySettingsView: View {
    @ObservedObject private var relay = PetRelayController.shared
    @State private var nickname = ""
    @State private var code = ""
    @State private var confirmDisconnect = false
    @State private var showInteractionPreview = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Label("Pet messages", systemImage: "envelope.fill").font(.title3.bold())
                    Spacer()
                    if relay.isBusy { ProgressView().controlSize(.small) }
                    if relay.mailbox.deviceID != nil {
                        Text(relay.connected ? "Relay connected" : "Reconnecting…")
                            .font(.caption).foregroundStyle(relay.connected ? .green : .secondary)
                        Button { Task { await relay.refresh() } } label: { Image(systemName: "arrow.clockwise") }
                            .help("Refresh pet messages")
                    }
                }
                Text("Pair two pets to send messages and interact. Click an interaction bubble to replay; it stays until you close it.")
                    .font(.caption).foregroundStyle(.secondary)
                Button { showInteractionPreview = true } label: {
                    Label("Preview pet interactions", systemImage: "sparkles")
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("pet-interaction-preview")
                if let error = relay.persistenceError ?? relay.error {
                    Text(error).font(.caption).foregroundStyle(.orange).textSelection(.enabled)
                }
                if let pair = relay.pair {
                    HStack(spacing: 12) {
                        PetRelayAvatar(profile: pair.peerPet, size: 88)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(verbatim: pair.peerPet?.name ?? pair.peerName).font(.headline)
                            Text(pair.peerPet == nil ? "Pet appearance unavailable" : "Your paired pet")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    HStack {
                        Label(pair.peerName, systemImage: "link").font(.headline)
                        Spacer()
                        Button("Unpair", role: .destructive) { confirmDisconnect = true }
                    }
                    HStack {
                        TextField("Your nickname (up to 20 characters)", text: $nickname)
                            .textFieldStyle(.roundedBorder)
                        Button("Save nickname") { Task { await relay.rename(nickname) } }
                            .disabled(relay.isBusy || !PetRelayValidation.validText(nickname) || nickname == relay.mailbox.name)
                    }
                    Text("Click your desktop pet to send a message. Reply directly from its message bubble.")
                        .font(.caption).foregroundStyle(.secondary)
                    PetTogetherControls(relay: relay)
                } else {
                    pairing
                }
                Divider()
                Text("Pairing shares your nickname, pet name, appearance and messages. Imported pets share a small portrait. No pet levels, usage data or AI configuration is uploaded. This relay uses HTTPS, not end-to-end encryption. Offline interactions keep a replay bubble. Older animations play only when you click it.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            .padding(20)
        }
        .onAppear {
            nickname = relay.mailbox.deviceID == nil ? NSLocalizedString("Pet friend", comment: "default relay nickname") : relay.mailbox.name
            relay.start()
            Task { await relay.refresh() }
        }
        .confirmationDialog("Unpair these pets?", isPresented: $confirmDisconnect) {
            Button("Unpair", role: .destructive) { Task { await relay.disconnect() } }
        } message: { Text("Unread messages remain until you close them. You can pair again with a new code.") }
        .sheet(isPresented: $showInteractionPreview) { PetInteractionPreviewView() }
    }

    private var pairing: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("Your nickname (up to 20 characters)", text: $nickname)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("relay-nickname")
            if let invitation = relay.mailbox.invitation,
               Date(timeIntervalSince1970: invitation.expiresAt) > Date() {
                if invitation.isCreator {
                    Text(verbatim: invitation.code)
                        .font(.system(size: 32, weight: .bold, design: .monospaced)).textSelection(.enabled)
                        .accessibilityIdentifier("relay-pair-code")
                    HStack {
                        Button("Copy pairing code") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(invitation.code, forType: .string)
                        }
                        Text("Valid until")
                        Text(Date(timeIntervalSince1970: invitation.expiresAt), style: .time)
                    }.font(.caption)
                    if invitation.awaitingConfirmation, let name = invitation.peerName {
                        Text(String(format: NSLocalizedString("%@ wants to pair with you.", comment: "pair request"), name))
                        Button("Confirm pairing") { Task { await relay.confirm() } }
                            .buttonStyle(.borderedProminent).disabled(relay.isBusy)
                    } else {
                        Text("Ask your friend to enter this code, then confirm their request here.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                } else {
                    Text("Waiting for your friend to confirm pairing…")
                    if let name = invitation.peerName { Text(verbatim: name).font(.headline) }
                }
                Button("Cancel invitation") { Task { await relay.disconnect() } }.disabled(relay.isBusy)
            } else {
                Button("Create pairing code") { Task { await relay.createInvitation(name: nickname) } }
                    .buttonStyle(.borderedProminent)
                    .disabled(relay.isBusy || !PetRelayValidation.validText(nickname))
                HStack {
                    TextField("Friend's 6-character code", text: $code)
                        .textFieldStyle(.roundedBorder).font(.system(.body, design: .monospaced))
                        .accessibilityIdentifier("relay-join-code")
                    Button("Request pairing") { Task { await relay.join(code: code, name: nickname) } }
                        .disabled(relay.isBusy || !PetRelayValidation.validCode(code) || !PetRelayValidation.validText(nickname))
                }
                Text("Codes contain both letters and digits, ignore case and expire in 10 minutes. A code pairs only two devices.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

}

/// Display-only state. Expanding never changes the durable mailbox or sends a receipt.
struct PetMessageExpansion {
    var isExpanded = false
    mutating func toggle() { isExpanded.toggle() }
    func ordered(_ messages: [PetRelayMessage]) -> [PetRelayMessage] {
        messages.sorted { ($0.createdAt, $0.id) < ($1.createdAt, $1.id) }
    }
}

struct PetMessageBubble: View {
    @ObservedObject private var relay: PetRelayController
    @ObservedObject private var settings = BubbleSettings.shared
    @State private var expansion: PetMessageExpansion

    init(relay: PetRelayController = .shared, initiallyExpanded: Bool = false) {
        self.relay = relay
        _expansion = State(initialValue: PetMessageExpansion(isExpanded: initiallyExpanded))
    }
    private var messages: [PetRelayMessage] { expansion.ordered(relay.incoming.filter { $0.interaction == nil }) }

    var body: some View {
        if let message = messages.first {
            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    Button { expansion.toggle() } label: {
                        HStack {
                            Label(message.senderName, systemImage: "envelope.fill").lineLimit(1)
                            Spacer()
                            if messages.count > 1 { Text("+\(messages.count - 1)").monospacedDigit() }
                            Image(systemName: expansion.isExpanded ? "chevron.up" : "chevron.down")
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(expansion.isExpanded ? "Collapse messages" : "Expand messages")
                    .accessibilityLabel(expansion.isExpanded ? "Collapse messages" : "Expand messages")
                    .accessibilityIdentifier("relay-expand-messages")
                    if !expansion.isExpanded { closeButton(message) }
                }
                .font(.system(size: settings.fontSize.secondaryPt, weight: .semibold))
                if expansion.isExpanded {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(messages) { item in
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack {
                                        Text(verbatim: item.senderName).lineLimit(1)
                                        Text(Date(timeIntervalSince1970: item.createdAt), format: .dateTime.month().day().hour().minute().second())
                                            .font(.caption2).opacity(0.7)
                                        Spacer(minLength: 2)
                                        closeButton(item)
                                    }
                                    .font(.caption)
                                    content(item)
                                    replyButton(item).frame(maxWidth: .infinity, alignment: .trailing)
                                }
                                if item.id != messages.last?.id { Divider() }
                            }
                        }
                        .padding(.trailing, 5)
                    }
                    .frame(height: min(280, CGFloat(messages.count) * 126))
                    .accessibilityIdentifier("relay-expanded-messages")
                } else {
                    Button { expansion.toggle() } label: {
                        content(message).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain).help("Expand messages")
                    HStack {
                        Text("Stays until closed or replied").font(.system(size: 10)).opacity(0.65)
                        Spacer()
                        replyButton(message)
                    }
                }
                if let error = relay.persistenceError ?? relay.error { Text(error).font(.caption2).foregroundStyle(.orange) }
            }
            .foregroundStyle(foreground)
            .padding(12).frame(width: expansion.isExpanded ? 320 : 270)
            .background(RoundedRectangle(cornerRadius: 15).fill(background))
            .overlay(RoundedRectangle(cornerRadius: 15).strokeBorder(Color.pink.opacity(0.4), lineWidth: 1))
            .shadow(color: .black.opacity(0.14), radius: 4, y: 2)
            .accessibilityIdentifier("relay-message-bubble")
        }
    }
    private func content(_ message: PetRelayMessage) -> some View {
        HStack(spacing: 8) {
            if message.senderPet != nil { PetRelayAvatar(profile: message.senderPet, size: 40) }
            Text(verbatim: message.displayContent)
                .font(.system(size: message.icon != nil ? 32 : settings.fontSize.primaryPt))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
    private func closeButton(_ message: PetRelayMessage) -> some View {
        Button { relay.dismiss(message.id) } label: { Image(systemName: "xmark").font(.caption.bold()) }
            .buttonStyle(.plain).help("Close this pet message")
            .accessibilityIdentifier("relay-dismiss-message")
    }
    private func replyButton(_ message: PetRelayMessage) -> some View {
        HStack(spacing: 6) {
            Button("Reply") { PetWindowController.shared.showMessageComposer(replyTo: message) }
                .accessibilityIdentifier("relay-reply-message")
            if let gesture = message.interaction {
                Button(InterfaceText.format(gesture == .hug ? "Hug back" : "Poke back")) {
                    Task { await relay.send(replyTo: message.id, expectedPairID: message.pairID,
                                            gesture: gesture == .hug ? .hug : .poke) }
                }
                .disabled(!relay.supportsInteractions || relay.isBusy)
                .accessibilityIdentifier("relay-quick-reply")
            }
        }
        .buttonStyle(.bordered).controlSize(.small)
        .disabled(message.pairID != relay.pair?.id)
    }
    private var foreground: Color {
        switch settings.theme { case .light: .black; case .dark: .white; case .system: .primary }
    }
    private var background: Color {
        switch settings.theme {
        case .light: .white.opacity(settings.opacity)
        case .dark: Color(red: 0.11, green: 0.12, blue: 0.15).opacity(settings.opacity)
        case .system: Color(nsColor: .textBackgroundColor).opacity(settings.opacity)
        }
    }
}
