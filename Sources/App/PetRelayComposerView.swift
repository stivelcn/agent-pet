import SwiftUI
import AgentPetCore

/// Native popover content: one short message or gesture, right beside the desktop pet.
struct PetRelayComposerView: View {
    @ObservedObject var model: PetRelayComposerModel
    @ObservedObject private var relay: PetRelayController
    @ObservedObject private var language = AppLanguage.shared
    @ObservedObject private var update = AppUpdateController.shared
    @FocusState private var inputFocused: Bool
    let onClose: () -> Void

    init(model: PetRelayComposerModel, onClose: @escaping () -> Void) {
        self.model = model
        relay = model.relay
        self.onClose = onClose
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 7) {
                Image(systemName: model.replyTo == nil ? "envelope.fill" : "arrowshape.turn.up.left.fill")
                    .foregroundStyle(.pink)
                Text(InterfaceText.format(model.replyTo == nil ? "Send a pet message" : "Reply"))
                    .font(.system(size: 12, weight: .semibold))
                if let name = model.peerName {
                    Text(verbatim: name).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 0)
                Button(action: onClose) { Image(systemName: "xmark").font(.system(size: 10, weight: .bold)) }
                    .buttonStyle(.plain).keyboardShortcut(.cancelAction)
                    .help("Close composer").accessibilityIdentifier("relay-close-composer")
            }
            if let message = model.replyTo {
                Text(verbatim: message.displayContent)
                    .font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8).background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
            }
            if model.pairID == nil {
                Text(InterfaceText.format("Pair your pets first, then send messages right here."))
                    .font(.caption).foregroundStyle(.secondary)
                Button(InterfaceText.format("Open pairing settings")) {
                    onClose()
                    SettingsWindowController.shared.show(tab: .relay)
                }
                .buttonStyle(.borderedProminent)
            } else {
                composer
            }
        }
        .padding(14).frame(width: 300)
        .environment(\.locale, language.locale)
        .accessibilityIdentifier("relay-desktop-composer")
        .disabled(update.phase == .installing)
        .task { await Task.yield(); inputFocused = model.validContext }
        .onChange(of: model.didSend) { _, sent in if sent { onClose() } }
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 9) {
            if model.validContext {
                HStack(spacing: 8) {
                    PetRelayAvatar(profile: relay.pair?.peerPet, size: 56)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(verbatim: relay.pair?.peerPet?.name ?? model.peerName ?? "")
                            .font(.caption.bold()).lineLimit(1)
                        HStack(spacing: 6) {
                            ForEach(PetRelayGesture.allCases) { gesture in
                                Button(InterfaceText.format(gesture.labelKey)) {
                                    Task { if await model.sendGesture(gesture) { onClose() } }
                                }
                                .controlSize(.small).disabled(!model.canSend || !relay.supportsInteractions)
                                .accessibilityIdentifier("relay-send-" + gesture.rawValue)
                            }
                        }
                    }
                }
                if !relay.supportsInteractions {
                    Text(InterfaceText.format("Pet interactions need an updated relay and both pets online at least once."))
                        .font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                Divider()
                PetTogetherControls(relay: relay)
                Divider()
            }
            HStack(spacing: 8) {
                TextField(InterfaceText.format("Say something…"), text: $model.text)
                    .textFieldStyle(.roundedBorder).font(.system(size: 13))
                    .focused($inputFocused)
                    .disabled(!model.validContext || model.waitingForRetry || model.submitting)
                    .accessibilityIdentifier("relay-message-text")
                    .onSubmit { sendText() }
                Button { sendText() } label: {
                    Image(systemName: "arrow.up.circle.fill").font(.system(size: 25))
                }
                .buttonStyle(.plain).foregroundStyle(model.canSendText ? Color.accentColor : .secondary)
                .disabled(!model.canSendText)
                .help("Send").accessibilityLabel("Send").accessibilityIdentifier("relay-send-message")
            }
            HStack {
                Text(InterfaceText.format("Enter to send · Esc to close")).font(.system(size: 10)).foregroundStyle(.secondary)
                Spacer()
                Text("\(PetRelayValidation.trimmedText(model.text).count)/20")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(PetRelayValidation.trimmedText(model.text).count > 20 ? .red : .secondary)
            }
            HStack(spacing: 0) {
                ForEach(PetRelayIcon.allCases) { icon in
                    Button { Task { if await model.sendIcon(icon) { onClose() } } } label: {
                        Text(verbatim: icon.symbol).font(.system(size: 23)).frame(maxWidth: .infinity).padding(.vertical, 4)
                    }
                    .buttonStyle(.plain).disabled(!model.canSend)
                    .help(NSLocalizedString(icon.labelKey, comment: "relay preset icon"))
                    .accessibilityLabel(NSLocalizedString(icon.labelKey, comment: "relay preset icon"))
                }
            }
            if model.waitingForRetry {
                Text(InterfaceText.format(relay.mailbox.outbox.first(where: { $0.id == model.queuedDraftID })?.gesture == nil
                     ? "Saved for retry. This message will send automatically after reconnecting."
                     : "This visit will retry for up to 30 seconds, then expire."))
                    .font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Button(InterfaceText.format("Cancel retry")) { model.cancelRetry(); inputFocused = true }
                    .controlSize(.small).disabled(relay.isBusy || model.submitting)
            } else if !model.validContext && !model.didSend {
                Text(InterfaceText.format("This conversation changed. Close this box and open a new message from your pet."))
                    .font(.caption2).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
            }
            if !otherDrafts.isEmpty {
                Divider()
                Text(InterfaceText.format("Pending sends")).font(.caption2).foregroundStyle(.secondary)
                ScrollView {
                    VStack(spacing: 6) {
                        ForEach(otherDrafts) { draft in
                            HStack {
                                Text(verbatim: draft.content).font(.caption).lineLimit(1)
                                Spacer()
                                Button(InterfaceText.format("Cancel retry")) { relay.discardDraft(draft.id) }
                                    .controlSize(.mini).disabled(relay.isBusy || model.submitting)
                            }
                        }
                    }
                }
                .frame(height: CGFloat(min(otherDrafts.count, 3)) * 28)
            }
            if let error = relay.persistenceError ?? relay.error {
                Text(error).font(.caption2).foregroundStyle(.orange).lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if model.submitting { ProgressView().controlSize(.small) }
        }
    }
    private var otherDrafts: [PetRelayDraft] {
        relay.mailbox.outbox.filter { $0.id != model.queuedDraftID }
    }
    private func sendText() {
        Task { if await model.sendText() { onClose() } }
    }
}
