import AppKit
import SwiftUI
import AgentPetCore

/// Settings manage the pairing only. Sending and replying live beside the pet.
struct PetRelaySettingsView: View {
    @ObservedObject private var relay = PetRelayController.shared
    @State private var nickname = ""
    @State private var code = ""
    @State private var confirmDisconnect = false

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
                Text("Pair two pets to send short messages and little gestures. Unread bubbles stay until you close or reply to them.")
                    .font(.caption).foregroundStyle(.secondary)
                if let error = relay.persistenceError ?? relay.error {
                    Text(error).font(.caption).foregroundStyle(.orange).textSelection(.enabled)
                }
                if let pair = relay.pair {
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
                    Text("Send from your desktop pet's right-click menu. Reply directly from its message bubble.")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    pairing
                }
                Divider()
                Text("Only your chosen nickname and messages are sent. No pet levels, usage data or AI configuration is uploaded. This relay uses HTTPS, not end-to-end encryption. A sleeping or closed app receives messages after reconnecting.")
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

struct PetMessageBubble: View {
    @ObservedObject private var relay = PetRelayController.shared
    @ObservedObject private var settings = BubbleSettings.shared
    var body: some View {
        if let message = relay.incoming.first {
            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    Label(message.senderName, systemImage: "envelope.fill")
                        .font(.system(size: settings.fontSize.secondaryPt, weight: .semibold)).lineLimit(1)
                    Spacer()
                    if relay.incoming.count > 1 { Text("+\(relay.incoming.count - 1)").font(.caption.monospacedDigit()) }
                    Button { relay.dismiss(message.id) } label: { Image(systemName: "xmark").font(.caption.bold()) }
                        .buttonStyle(.plain).help("Close this pet message")
                        .accessibilityIdentifier("relay-dismiss-message")
                }
                Text(verbatim: message.content)
                    .font(.system(size: message.icon != nil ? 32 : settings.fontSize.primaryPt))
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Text("Stays until closed or replied").font(.system(size: 10)).opacity(0.65)
                    Spacer()
                    Button("Reply") {
                        PetWindowController.shared.showMessageComposer(replyTo: message)
                    }
                    .buttonStyle(.bordered).controlSize(.small)
                    .accessibilityIdentifier("relay-reply-message")
                    .disabled(message.pairID != relay.pair?.id)
                }
                if let error = relay.persistenceError { Text(error).font(.caption2).foregroundStyle(.orange) }
            }
            .foregroundStyle(foreground)
            .padding(12).frame(width: 270)
            .background(RoundedRectangle(cornerRadius: 15).fill(background))
            .overlay(RoundedRectangle(cornerRadius: 15).strokeBorder(Color.pink.opacity(0.4), lineWidth: 1))
            .shadow(color: .black.opacity(0.14), radius: 4, y: 2)
            .accessibilityIdentifier("relay-message-bubble")
        }
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
