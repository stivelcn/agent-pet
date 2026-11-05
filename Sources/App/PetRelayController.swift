import Foundation
import Combine
import AgentPetCore

@MainActor
final class PetRelayController: ObservableObject {
    static let shared = PetRelayController(
        fileURL: URL(fileURLWithPath: AgentPetPaths.baseDir).appendingPathComponent("pet-messages.json"),
        credentials: PetRelayKeychain(endpoint: PetRelayAPI.endpoint), api: PetRelayAPI(),
        enabled: ProcessInfo.processInfo.environment["AGENTPET_RELAY_ENABLED"] != "0")

    @Published private(set) var mailbox = PetRelayMailbox()
    @Published private(set) var isBusy = false
    @Published private(set) var connected = false
    @Published private(set) var error: String?
    @Published private(set) var persistenceError: String?
    private let fileURL: URL?
    private let credentialsStore: any PetRelayCredentialStore
    private let api: any PetRelayTransport
    private let enabled: Bool
    private let eventsEnabled: Bool
    private var credential: PetRelayCredentials?
    private var restoreFailed = false
    private var syncing = false
    private var started = false
    private var periodicTask: Task<Void, Never>?
    private var socketTask: Task<Void, Never>?

    init(fileURL: URL?, credentials: any PetRelayCredentialStore, api: any PetRelayTransport,
         enabled: Bool = true, events: Bool = true) {
        self.fileURL = fileURL; credentialsStore = credentials; self.api = api
        self.enabled = enabled; eventsEnabled = events
        if let fileURL, FileManager.default.fileExists(atPath: fileURL.path) {
            do { mailbox = try JSONDecoder().decode(PetRelayMailbox.self, from: Data(contentsOf: fileURL)) }
            catch { restoreFailed = true; persistenceError = PetRelayError.storage.localizedDescription }
        }
        guard enabled else { return }
        do {
            credential = try credentials.load()
            if let saved = mailbox.deviceID, let credential, saved != credential.deviceID {
                restoreFailed = true; persistenceError = PetRelayError.credentials.localizedDescription
            }
            if mailbox.deviceID != nil && credential == nil {
                restoreFailed = true; persistenceError = PetRelayError.credentials.localizedDescription
            }
        } catch { self.error = error.localizedDescription; restoreFailed = true }
    }

    var incoming: [PetRelayMessage] { mailbox.incoming }
    var pair: PetRelayPair? { mailbox.pair }

    func start() {
        guard enabled, !restoreFailed, !started else { return }
        started = true
        periodicTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                do { try await Task.sleep(for: .seconds(20)) } catch { break }
            }
        }
        startSocket()
    }
    func stop() {
        periodicTask?.cancel(); periodicTask = nil
        socketTask?.cancel(); socketTask = nil
        connected = false; started = false
    }
    private func startSocket() {
        guard started, eventsEnabled, socketTask == nil, let credential else { return }
        let api = api
        socketTask = Task { [weak self] in
            var delay = 1
            while !Task.isCancelled {
                let began = Date()
                do {
                    try await api.watch(token: credential.token) { [weak self] in await self?.refresh() }
                } catch { /* REST catch-up remains available when a proxy closes WSS. */ }
                guard !Task.isCancelled else { return }
                if Date().timeIntervalSince(began) > 60 { delay = 1 }
                do { try await Task.sleep(for: .seconds(delay)) } catch { return }
                delay = min(delay * 2, 30)
            }
        }
    }

    @discardableResult
    private func save() -> Bool {
        guard !restoreFailed else { return false }
        do {
            if let fileURL {
                try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                try JSONEncoder().encode(mailbox).write(to: fileURL, options: .atomic)
                try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
            }
            persistenceError = nil
            return true
        } catch { persistenceError = PetRelayError.storage.localizedDescription; return false }
    }

    func saveForUpdate() throws {
        guard !isBusy, !syncing else { throw AppUpdateError.message("Please wait for pet messaging to finish before installing.") }
        guard save() else { throw AppUpdateError.message("User data could not be saved. Installation was stopped.") }
    }

    private func apply(_ snapshot: PetRelaySnapshot) throws {
        guard snapshot.deviceID == credential?.deviceID else { throw PetRelayError.credentials }
        mailbox.merge(snapshot)
        guard save() else { throw PetRelayError.storage }
    }

    private func fetch(_ path: String, body: Data? = nil) async throws {
        guard let credential else { throw PetRelayError.credentials }
        let snapshot = try await api.fetch(path, token: credential.token, body: body)
        try apply(snapshot)
        connected = true
    }

    private func json(_ dictionary: [String: String]) throws -> Data { try JSONEncoder().encode(dictionary) }

    private func ensureCredential(name: String) async throws {
        guard credential == nil else { return }
        let result = try await api.register(name: name)
        try credentialsStore.save(result)
        credential = result
        mailbox.deviceID = result.deviceID
        mailbox.name = name
        guard save() else { throw PetRelayError.storage }
        startSocket()
    }

    /// The UI and the background sync share one serial REST lane, so an older
    /// snapshot can never resurrect a dismissed message or undo a new pairing.
    private func run(_ action: () async throws -> Void) async {
        guard enabled, !restoreFailed, !isBusy else { return }
        isBusy = true
        defer { isBusy = false }
        error = nil
        do {
            while syncing { try await Task.sleep(for: .milliseconds(30)) }
            try await action()
            try await flushAcknowledgements()
        } catch {
            if !(error is CancellationError) { self.error = error.localizedDescription }
        }
    }

    func createInvitation(name: String) async {
        await run {
            guard PetRelayValidation.validText(name) else { throw PetRelayError.server("invalid_text") }
            try await ensureCredential(name: PetRelayValidation.trimmedText(name))
            try await fetch("v1/device/name", body: json(["name": PetRelayValidation.trimmedText(name)]))
            try await fetch("v1/pairing/create", body: Data("{}".utf8))
        }
    }
    func join(code: String, name: String) async {
        await run {
            guard PetRelayValidation.validCode(code) else { throw PetRelayError.server("invalid_code") }
            guard PetRelayValidation.validText(name) else { throw PetRelayError.server("invalid_text") }
            try await ensureCredential(name: PetRelayValidation.trimmedText(name))
            try await fetch("v1/device/name", body: json(["name": PetRelayValidation.trimmedText(name)]))
            try await fetch("v1/pairing/join", body: json(["code": PetRelayValidation.normalizedCode(code)]))
        }
    }
    func confirm() async {
        await run {
            guard let invitation = mailbox.invitation else { return }
            try await fetch("v1/pairing/confirm", body: json(["code": invitation.code]))
        }
    }
    func disconnect() async {
        await run { try await fetch("v1/pairing/disconnect", body: Data("{}".utf8)) }
    }
    func rename(_ name: String) async {
        await run {
            guard PetRelayValidation.validText(name) else { throw PetRelayError.server("invalid_text") }
            try await fetch("v1/device/name", body: json(["name": PetRelayValidation.trimmedText(name)]))
        }
    }
    func refresh() async {
        guard enabled, !restoreFailed, credential != nil, !isBusy, !syncing else { return }
        syncing = true
        defer { syncing = false }
        do {
            try await fetch("v1/sync")
            try await flushAcknowledgements()
            // Never retarget old queued messages after pairing with someone new.
            for draft in mailbox.outbox where draft.pairID == mailbox.pair?.id {
                try await transmit(draft)
            }
            error = nil
        } catch {
            connected = false
            self.error = error.localizedDescription
        }
    }

    private func flushAcknowledgements() async throws {
        struct Ack: Encodable { var kind: String; var ids: [String] }
        // Local durable save MUST precede both kinds of delivery receipt.
        guard save() else { throw PetRelayError.storage }
        for kind in ["handled", "delivered"] {
            let ids = Array(kind == "handled" ? mailbox.handled : mailbox.delivered)
            for start in stride(from: 0, to: ids.count, by: 200) {
                let batch = Array(ids[start..<min(start + 200, ids.count)])
                try await fetch("v1/messages/ack", body: JSONEncoder().encode(Ack(kind: kind, ids: batch)))
                if kind == "handled" { mailbox.handled.subtract(batch) }
                else { mailbox.delivered.subtract(batch) }
                guard save() else { throw PetRelayError.storage }
            }
        }
    }

    func dismiss(_ id: String) {
        let before = mailbox
        mailbox.dismiss(id)
        guard save() else { mailbox = before; return }
        Task { await refresh() }
    }

    @discardableResult
    func send(text: String? = nil, icon: PetRelayIcon? = nil, replyTo: String? = nil, expectedPairID: String? = nil) async -> Bool {
        var accepted = false
        await run {
            guard let pair = mailbox.pair, expectedPairID == nil || expectedPairID == pair.id else {
                throw PetRelayError.server("not_paired")
            }
            if let text, !PetRelayValidation.validText(text) { throw PetRelayError.server("invalid_text") }
            guard (text == nil) != (icon == nil) else { throw PetRelayError.server("invalid_text") }
            if let replyTo, !mailbox.incoming.contains(where: { $0.id == replyTo && $0.pairID == pair.id }) {
                throw PetRelayError.server("not_paired")
            }
            guard mailbox.outbox.count < 20 else { throw PetRelayError.server("rate_limited") }
            let draft = PetRelayDraft(pairID: pair.id, text: text.map(PetRelayValidation.trimmedText), icon: icon, replyTo: replyTo)
            mailbox.outbox.append(draft)
            guard save() else { mailbox.outbox.removeAll { $0.id == draft.id }; throw PetRelayError.storage }
            try await transmit(draft)
            accepted = true
        }
        return accepted
    }

    private func transmit(_ draft: PetRelayDraft) async throws {
        struct Payload: Encodable {
            var clientID: String; var pairID: String; var text: String?; var icon: PetRelayIcon?; var replyTo: String?
        }
        let payload = Payload(clientID: draft.id, pairID: draft.pairID, text: draft.text, icon: draft.icon, replyTo: draft.replyTo)
        try await fetch("v1/messages", body: JSONEncoder().encode(payload))
        mailbox.accept(draft.id)
        guard save() else { throw PetRelayError.storage }
    }
    func discardDraft(_ id: String) {
        let before = mailbox
        mailbox.outbox.removeAll { $0.id == id }
        if !save() { mailbox = before }
    }
}
