import Foundation
import AppKit
import SwiftUI
import Testing
import AgentPetCore
@testable import agentpet

private actor RelayMockAPI: PetRelayTransport {
    var state: PetRelaySnapshot
    var paths: [String] = []
    var fail = false
    var failSend = false
    var payloads: [Data] = []
    var acknowledgements: [Data] = []
    init(incoming: Bool = true) {
        state = PetRelaySnapshot(deviceID: "device1", name: "噜妹", pair: PetRelayPair(id: "pair1", peerName: "噜噜"),
            incoming: incoming ? [PetRelayMessage(id: "m1", clientID: "incoming-client1", pairID: "pair1", senderName: "噜噜", text: "喝水", createdAt: 1)] : [])
    }
    func setFail(_ value: Bool) { fail = value }
    func setFailSend(_ value: Bool) { failSend = value }
    func receive(_ message: PetRelayMessage) { state.incoming.append(message) }
    func enableInteractions() {
        state.capabilities = ["pet-interactions-v1"]
        state.pair?.peerPet = PetRelayPetProfile(name: "噜噜", builtinID: "lulu")
    }
    func unpair() { state.pair = nil }
    func newPair() { state.pair = PetRelayPair(id: "pair2", peerName: "New friend") }
    func register(name: String) async throws -> PetRelayCredentials {
        paths.append("register")
        return PetRelayCredentials(deviceID: "device1", token: "isolated-test-token")
    }
    func fetch(_ path: String, token: String, body: Data?) async throws -> PetRelaySnapshot {
        paths.append(path)
        if fail || (path == "v1/messages" && failSend) { throw URLError(.notConnectedToInternet) }
        let data = body.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? [:]
        if path == "v1/device/pet", let body {
            state.pet = try JSONDecoder().decode(PetRelayPetProfile.self, from: body)
        }
        if path == "v1/messages/ack", let ids = data["ids"] as? [String] {
            if let body { acknowledgements.append(body) }
            if data["kind"] as? String == "handled" { state.incoming.removeAll { ids.contains($0.id) } }
            else {
                for index in state.incoming.indices where ids.contains(state.incoming[index].id) { state.incoming[index].deliveredAt = 2 }
            }
        }
        if path == "v1/messages", let body {
            payloads.append(body)
            if let clientID = data["clientID"] as? String, let pairID = data["pairID"] as? String {
                let reply = data["replyTo"] as? String
                state.sent.insert(PetRelayMessage(id: UUID().uuidString, clientID: clientID, pairID: pairID,
                    senderName: "噜妹", text: data["text"] as? String, icon: (data["icon"] as? String).flatMap(PetRelayIcon.init(rawValue:)),
                    replyTo: reply, createdAt: 3, gesture: data["gesture"] as? String,
                    expiresAt: data["expiresAt"] as? Double, senderPet: state.pet), at: 0)
                if let reply { state.incoming.removeAll { $0.id == reply } }
            }
        }
        return state
    }
    func watch(token: String, changed: @escaping @Sendable () async -> Void) async throws {}
}

private actor RelayEventProbe {
    private(set) var count = 0
    func bump() { count += 1 }
}

@MainActor private final class RelayMockCredential: PetRelayCredentialStore {
    var value: PetRelayCredentials?
    init(present: Bool = true) { value = present ? PetRelayCredentials(deviceID: "device1", token: "isolated-test-token") : nil }
    func load() throws -> PetRelayCredentials? { value }
    func save(_ credentials: PetRelayCredentials) throws { value = credentials }
}

@MainActor private final class RelayProfileFixture {
    var value = PetRelayPetProfile(name: "噜噜", builtinID: "lulu")
}

@MainActor
@Suite(.serialized)
struct PetRelayIntegrationTests {
    private func folder() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("agentpet-relay-tests-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
    private func controller(_ api: RelayMockAPI, file: URL? = nil, credential: RelayMockCredential? = nil) -> PetRelayController {
        PetRelayController(fileURL: file, credentials: credential ?? RelayMockCredential(), api: api, events: false)
    }
    @Test func startupWithoutOptInDoesNotRegisterOrUploadAnything() async {
        let api = RelayMockAPI()
        let relay = controller(api, credential: RelayMockCredential(present: false))
        await relay.refresh()
        #expect(await api.paths.isEmpty)
        #expect(relay.mailbox.deviceID == nil)
    }
    @Test func deliveryReceiptFollowsDurableLocalPersistenceAndRestartKeepsUnread() async throws {
        let directory = try folder(); defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("messages.json")
        let api = RelayMockAPI()
        let relay = controller(api, file: file)
        await relay.refresh()
        #expect(relay.incoming.count == 1)
        #expect(await api.paths.contains("v1/messages/ack"))
        let data = try Data(contentsOf: file)
        let box = try JSONDecoder().decode(PetRelayMailbox.self, from: data)
        #expect(box.incoming.count == 1)
        #expect(!String(decoding: data, as: UTF8.self).contains("isolated-test-token"))
        let restarted = controller(api, file: file)
        #expect(restarted.incoming.count == 1)
        #expect(restarted.incoming[0].id == "m1")
    }
    @Test func offlineDismissalPersistsUntilLaterAcknowledgement() async throws {
        let directory = try folder(); defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("messages.json")
        let api = RelayMockAPI()
        let relay = controller(api, file: file)
        await relay.refresh()
        await api.setFail(true)
        relay.dismiss("m1")
        await relay.refresh()
        let restarted = controller(api, file: file)
        #expect(restarted.incoming.isEmpty)
        #expect(restarted.mailbox.handled.contains("m1"))
        await api.setFail(false)
        await restarted.refresh()
        #expect(restarted.incoming.isEmpty)
        #expect(restarted.mailbox.handled.isEmpty)
    }
    @Test func failedReplyKeepsBubbleAndRetryUsesOriginalClientID() async {
        let api = RelayMockAPI()
        let relay = controller(api)
        await relay.refresh()
        await api.setFailSend(true)
        let accepted = await relay.send(text: "收到", replyTo: "m1")
        #expect(!accepted)
        #expect(relay.incoming.count == 1)
        #expect(relay.mailbox.outbox.count == 1)
        let clientID = relay.mailbox.outbox.first?.id
        await api.setFailSend(false)
        await relay.refresh()
        #expect(relay.incoming.isEmpty)
        #expect(relay.mailbox.outbox.isEmpty)
        #expect(relay.mailbox.sent.first?.clientID == clientID)
    }
    @Test func closingOrCancellingComposerDoesNotHandleMessage() async {
        let api = RelayMockAPI()
        let relay = controller(api)
        await relay.refresh()
        let paths = await api.paths
        var composer: PetRelayComposerModel? = PetRelayComposerModel(relay: relay, replyTo: relay.incoming.first)
        composer?.text = "草稿还没发送"
        #expect(composer?.canSendText == true)
        composer = nil // X, Escape and clicking outside only dismiss the native popover.
        #expect(await api.paths == paths)
        #expect(relay.incoming.count == 1)
        #expect(relay.mailbox.handled.isEmpty)
    }
    @Test func desktopComposerSendsTextReplyAndOnlyThenHandlesOriginal() async {
        let api = RelayMockAPI()
        let relay = controller(api)
        await relay.refresh()
        let composer = PetRelayComposerModel(relay: relay, replyTo: relay.incoming.first)
        composer.text = "这就喝水💧"
        #expect(relay.incoming.count == 1)
        #expect(composer.canSendText)
        #expect(await composer.sendText())
        #expect(composer.didSend)
        #expect(composer.text.isEmpty)
        #expect(relay.incoming.isEmpty)
        #expect(relay.mailbox.sent.first?.replyTo == "m1")
        #expect(!composer.canSend)
    }
    @Test func desktopComposerSendsGestureWithoutHandlingUnrelatedMessage() async {
        let api = RelayMockAPI()
        let relay = controller(api)
        await relay.refresh()
        let composer = PetRelayComposerModel(relay: relay)
        #expect(await composer.sendIcon(.heart))
        #expect(composer.didSend)
        #expect(relay.mailbox.sent.first?.icon == .heart)
        #expect(relay.mailbox.sent.first?.replyTo == nil)
        #expect(relay.incoming.count == 1)
    }
    @Test func desktopGestureReplyCarriesOriginalMessageIdentity() async {
        let api = RelayMockAPI()
        let relay = controller(api)
        await relay.refresh()
        let composer = PetRelayComposerModel(relay: relay, replyTo: relay.incoming.first)
        #expect(await composer.sendIcon(.hug))
        #expect(relay.mailbox.sent.first?.replyTo == "m1")
        #expect(relay.incoming.isEmpty)
    }
    @Test func desktopComposerQueuesFailedReplyWithoutDuplicatesAndCanCancelRetry() async {
        let api = RelayMockAPI()
        let relay = controller(api)
        await relay.refresh()
        await api.setFailSend(true)
        let composer = PetRelayComposerModel(relay: relay, replyTo: relay.incoming.first)
        composer.text = "收到啦"
        #expect(!(await composer.sendText()))
        #expect(composer.waitingForRetry)
        #expect(!composer.didSend)
        #expect(relay.incoming.count == 1)
        #expect(relay.mailbox.outbox.count == 1)
        #expect(!(await composer.sendIcon(.water)))
        #expect(relay.mailbox.outbox.count == 1)
        composer.cancelRetry()
        #expect(!composer.waitingForRetry)
        #expect(composer.text == "收到啦")
        #expect(composer.canSendText)
        #expect(relay.mailbox.outbox.isEmpty)
        #expect(relay.incoming.count == 1)
        #expect(relay.mailbox.handled.isEmpty)
    }
    @Test func desktopComposerRecognizesBackgroundRetrySuccess() async {
        let api = RelayMockAPI()
        let relay = controller(api)
        await relay.refresh()
        await api.setFailSend(true)
        let composer = PetRelayComposerModel(relay: relay, replyTo: relay.incoming.first)
        #expect(!(await composer.sendIcon(.water)))
        #expect(!composer.didSend)
        await api.setFailSend(false)
        await relay.refresh()
        #expect(composer.didSend)
        #expect(!composer.waitingForRetry)
        #expect(relay.incoming.isEmpty)
    }
    @Test func desktopComposerCountsVisibleCharactersAndRejectsLongText() async {
        let api = RelayMockAPI()
        let relay = controller(api)
        await relay.refresh()
        let composer = PetRelayComposerModel(relay: relay)
        composer.text = String(repeating: "中", count: 21)
        #expect(!composer.canSendText)
        #expect(!(await composer.sendText()))
        #expect(!(await api.paths.contains("v1/messages")))
        composer.text = String(repeating: "👨‍👩‍👧‍👦", count: 20)
        #expect(composer.canSendText)
        #expect(await composer.sendText())
    }
    @Test func desktopComposerNeverRetargetsToNewPairingOrDismissedReply() async {
        let api = RelayMockAPI()
        let relay = controller(api)
        await relay.refresh()
        let reply = PetRelayComposerModel(relay: relay, replyTo: relay.incoming.first)
        reply.text = "不要误发"
        relay.dismiss("m1")
        #expect(!reply.canSendText)
        #expect(!(await reply.sendText()))
        // A separate controller avoids the asynchronous handled-ACK scheduled by dismiss above.
        let newAPI = RelayMockAPI()
        let newRelay = controller(newAPI)
        await newRelay.refresh()
        let outgoing = PetRelayComposerModel(relay: newRelay)
        outgoing.text = "不能给新朋友"
        await newAPI.newPair()
        await newRelay.refresh()
        #expect(!outgoing.canSendText)
        #expect(!(await outgoing.sendText()))
        #expect(!(await newRelay.send(text: "旧上下文", expectedPairID: "pair1")))
        #expect(!(await newAPI.paths.contains("v1/messages")))
        await newAPI.unpair()
        await newRelay.refresh()
        let unpaired = PetRelayComposerModel(relay: newRelay)
        #expect(!(await unpaired.sendIcon(.heart)))
    }
    @Test func unpairRetainsInboxAndOldOutboxDoesNotGoToNewPartner() async {
        let api = RelayMockAPI()
        let relay = controller(api)
        await relay.refresh()
        await api.setFailSend(true)
        _ = await relay.send(text: "稍等")
        let attempts = await api.paths.filter { $0 == "v1/messages" }.count
        await api.unpair()
        await api.setFailSend(false)
        await relay.refresh()
        #expect(relay.incoming.count == 1)
        await api.newPair()
        await relay.refresh()
        #expect(relay.mailbox.outbox.count == 1)
        #expect(await api.paths.filter { $0 == "v1/messages" }.count == attempts)
    }
    @Test func invalidAndTooLongMessagesNeverEnterOutboxOrNetwork() async {
        let api = RelayMockAPI()
        let relay = controller(api)
        await relay.refresh()
        #expect(!(await relay.send(text: String(repeating: "中", count: 21))))
        #expect(!(await relay.send(text: "hi", icon: .heart)))
        #expect(relay.mailbox.outbox.isEmpty)
        #expect(!(await api.paths.contains("v1/messages")))
    }
    @Test func corruptedMailboxIsNotOverwrittenOrAcknowledged() async throws {
        let directory = try folder(); defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("messages.json")
        let original = Data("broken-but-preserve-me".utf8)
        try original.write(to: file)
        let api = RelayMockAPI()
        let relay = controller(api, file: file)
        await relay.refresh()
        await relay.createInvitation(name: "test")
        #expect(relay.persistenceError != nil)
        #expect(try Data(contentsOf: file) == original)
        #expect(await api.paths.isEmpty)
    }
    @Test func failedLocalSavePreventsDeliveryReceipt() async throws {
        let directory = try folder(); defer { try? FileManager.default.removeItem(at: directory) }
        let blocker = directory.appendingPathComponent("not-a-directory")
        try Data("blocker".utf8).write(to: blocker)
        let api = RelayMockAPI()
        let relay = controller(api, file: blocker.appendingPathComponent("messages.json"))
        await relay.refresh()
        #expect(relay.persistenceError != nil)
        #expect(relay.incoming.count == 1)
        #expect(!(await api.paths.contains("v1/messages/ack")))
    }
    @Test func apiPathsPreserveHTTPSRelayPrefix() {
        let api = PetRelayAPI()
        #expect(api.url("v1/sync").absoluteString == "https://imagepro.ycgod.online/agentpet-relay/v1/sync")
    }

    @Test func profileSyncIsCapabilityGatedAndOnlyUploadsChanges() async {
        let api = RelayMockAPI(incoming: false)
        let profile = PetRelayPetProfile(name: "噜妹", builtinID: "lumei")
        let relay = PetRelayController(fileURL: nil, credentials: RelayMockCredential(), api: api, events: false,
                                       profileProvider: { profile })
        await relay.refresh()
        #expect(!(await api.paths).contains("v1/device/pet"))
        await api.enableInteractions()
        await relay.refresh()
        await relay.refresh()
        #expect((await api.paths).filter { $0 == "v1/device/pet" }.count == 1)
        #expect(relay.mailbox.pet == profile)
        #expect(relay.pair?.peerPet?.builtinID == "lulu")
    }

    @Test func remoteGestureReplyEncodesExpiryAndCooldownKeepsOtherUnread() async throws {
        let api = RelayMockAPI()
        await api.enableInteractions()
        let relay = controller(api)
        await relay.refresh()
        let composer = PetRelayComposerModel(relay: relay, replyTo: relay.incoming.first)
        #expect(await composer.sendGesture(.poke))
        #expect(relay.incoming.isEmpty)
        let payload = try #require(await api.payloads.first)
        let data = try #require(try JSONSerialization.jsonObject(with: payload) as? [String: Any])
        #expect(data["gesture"] as? String == "poke")
        #expect(data["replyTo"] as? String == "m1")
        #expect((data["expiresAt"] as? Double ?? 0) > Date().timeIntervalSince1970)
        #expect(data["text"] == nil && data["icon"] == nil)
        #expect(!(await relay.send(gesture: .hug)))
        #expect(await api.payloads.count == 1)
    }

    @Test func legacyPeerCannotReceiveGesturesAndFailedReplyKeepsOriginal() async {
        let api = RelayMockAPI()
        let relay = controller(api)
        await relay.refresh()
        #expect(!(await relay.send(gesture: .poke)))
        #expect(relay.mailbox.outbox.isEmpty)
        await api.enableInteractions()
        await relay.refresh()
        await api.setFailSend(true)
        #expect(!(await relay.send(replyTo: "m1", expectedPairID: "pair1", gesture: .hug)))
        #expect(relay.incoming.map(\.id) == ["m1"])
        #expect(relay.mailbox.outbox.first?.gesture == .hug)
        await api.newPair()
        await api.setFailSend(false)
        await relay.refresh()
        #expect(await api.payloads.isEmpty)
        #expect(relay.incoming.map(\.id) == ["m1"])
    }

    @Test func expiredOutgoingVisitIsNotRetriedAndComposerCanSendAgain() async throws {
        let directory = try folder(); defer { try? FileManager.default.removeItem(at: directory) }
        let api = RelayMockAPI()
        await api.enableInteractions()
        var box = PetRelayMailbox()
        box.outbox = [PetRelayDraft(pairID: "pair1", replyTo: "m1", gesture: .poke, expiresAt: 1)]
        let file = directory.appendingPathComponent("messages.json")
        try JSONEncoder().encode(box).write(to: file)
        let relay = controller(api, file: file)
        await relay.refresh()
        #expect(relay.mailbox.outbox.isEmpty)
        #expect(await api.payloads.isEmpty)
        #expect(relay.incoming.count == 1)
        #expect(relay.error == PetRelayError.server("gesture_expired").localizedDescription)
        let composer = PetRelayComposerModel(relay: relay)
        #expect(composer.canSend)
    }

    @Test func consumedVisitIsSavedBeforeDisplayAndCannotReplayAfterRestart() async throws {
        let directory = try folder(); defer { try? FileManager.default.removeItem(at: directory) }
        var box = PetRelayMailbox()
        let now = Date().timeIntervalSince1970
        box.merge(PetRelaySnapshot(deviceID: "device1", name: "me", pair: PetRelayPair(id: "pair1", peerName: "friend"),
            incoming: [PetRelayMessage(id: "v", clientID: "v", pairID: "pair1", senderName: "friend", createdAt: now,
                                      gesture: "hug", expiresAt: now + 30)]))
        let file = directory.appendingPathComponent("messages.json")
        try JSONEncoder().encode(box).write(to: file)
        let relay = controller(RelayMockAPI(), file: file)
        #expect(relay.consumeInteractions(canAnimate: true)?.interaction == .hug)
        let restart = controller(RelayMockAPI(), file: file)
        #expect(restart.consumeInteractions(canAnimate: true) == nil)
        #expect(restart.incoming.count == 1)
        #expect(restart.mailbox.replayInteraction("v")?.interaction == .hug)
        #expect(restart.mailbox.handled.isEmpty)
    }

    @Test func replayIsOfflineAndOnlyClosingSendsHandledReceipt() async throws {
        let directory = try folder(); defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("messages.json")
        let api = RelayMockAPI(incoming: false)
        let visit = PetRelayMessage(id: "visit", clientID: "v", pairID: "pair1", senderName: "噜妹",
            createdAt: 1, gesture: "hug", expiresAt: 31, senderPet: PetRelayPetProfile(name: "噜妹", builtinID: "lumei"))
        await api.receive(visit)
        let relay = controller(api, file: file)
        await relay.refresh()
        #expect(relay.consumeInteractionBatch(canAnimate: true).isEmpty)
        let before = relay.mailbox
        let paths = await api.paths
        let player = PetPairInteractionPlayer()
        for _ in 0..<100 {
            player.replay(try #require(relay.mailbox.replayInteraction("visit")))
            player.finish(try #require(player.active?.id))
        }
        #expect(relay.mailbox == before)
        #expect(await api.paths == paths)
        // Even an explicitly requested reply must not let the server handle the interaction.
        #expect(await relay.send(text: "收到啦", replyTo: "visit", expectedPairID: "pair1"))
        let payload = try #require(await api.payloads.last)
        let object = try #require(JSONSerialization.jsonObject(with: payload) as? [String: Any])
        #expect(object["replyTo"] == nil)
        #expect(relay.mailbox.replayInteraction("visit") != nil)
        relay.dismiss("visit")
        await relay.refresh()
        #expect(relay.mailbox.replayInteraction("visit") == nil)
        let acks = try await api.acknowledgements.map { try JSONSerialization.jsonObject(with: $0) as! [String: Any] }
        #expect(acks.contains { $0["kind"] as? String == "handled" && ($0["ids"] as? [String])?.contains("visit") == true })
        let restart = controller(api, file: file)
        await restart.refresh()
        #expect(restart.mailbox.replayInteraction("visit") == nil)
    }

    @Test func sleepingReceivesAndPersistsAllMessagesWithoutHandlingOrReplayingThemOnWake() async throws {
        let directory = try folder(); defer { try? FileManager.default.removeItem(at: directory) }
        let suite = "local.agentpet.tests.sleep-relay.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let sleep = PetSleepController(defaults: defaults)
        sleep.goToSleep()
        let api = RelayMockAPI(incoming: false)
        await api.enableInteractions()
        let file = directory.appendingPathComponent("messages.json")
        let relay = PetRelayController(fileURL: file, credentials: RelayMockCredential(), api: api,
                                       events: false, isSleeping: { sleep.isSleeping })
        let now = Date().timeIntervalSince1970
        let messages = [
            PetRelayMessage(id: "sleep-text", clientID: "sleep-text", pairID: "pair1", senderName: "噜噜", text: "醒来记得查收", createdAt: now),
            PetRelayMessage(id: "sleep-icon", clientID: "sleep-icon", pairID: "pair1", senderName: "噜噜", icon: .heart, createdAt: now),
        ] + [PetRelayGesture.hug, .poke].map { gesture in
            PetRelayMessage(id: "sleep-\(gesture.rawValue)", clientID: "sleep-\(gesture.rawValue)", pairID: "pair1",
                senderName: "噜噜", createdAt: now, gesture: gesture.rawValue, expiresAt: now + 30,
                senderPet: PetRelayPetProfile(name: "噜噜", builtinID: "lulu"))
        }
        for message in messages {
            await api.receive(message)
            await relay.refresh()
        }
        #expect(Set(relay.incoming.map(\.id)) == Set(messages.map(\.id)))
        #expect(relay.mailbox.handled.isEmpty)
        #expect(relay.consumeInteractionBatch(canAnimate: true).isEmpty)
        let restartedSleep = PetSleepController(defaults: defaults)
        #expect(restartedSleep.isSleeping)
        let restarted = PetRelayController(fileURL: file, credentials: RelayMockCredential(), api: api,
                                           events: false, isSleeping: { restartedSleep.isSleeping })
        await restarted.refresh()
        restartedSleep.wakeUp()
        #expect(restarted.consumeInteractionBatch(canAnimate: true).isEmpty)
        #expect(restarted.incoming.count == 4)
        for id in ["sleep-hug", "sleep-poke"] {
            for _ in 0..<20 { #expect(restarted.mailbox.replayInteraction(id)?.id == id) }
        }
        let acks = try await api.acknowledgements.map { try JSONSerialization.jsonObject(with: $0) as! [String: Any] }
        #expect(!acks.isEmpty && acks.allSatisfy { $0["kind"] as? String == "delivered" })
        #expect(await api.payloads.isEmpty)
        // Newly arriving interactions play normally after waking, while all folded bubbles remain.
        await api.receive(PetRelayMessage(id: "awake-peek", clientID: "awake-peek", pairID: "pair1", senderName: "噜噜",
            createdAt: now + 1, gesture: "peek", expiresAt: now + 30,
            senderPet: PetRelayPetProfile(name: "噜噜", builtinID: "lulu")))
        await restarted.refresh()
        #expect(restarted.consumeInteractionBatch(canAnimate: true).map(\.id) == ["awake-peek"])
        #expect(restarted.incoming.count == 5 && restarted.mailbox.handled.isEmpty)
    }

    @Test func pairedComposerRendersPeerAndActionsOffscreen() async throws {
        _ = NSApplication.shared
        let api = RelayMockAPI(incoming: false)
        await api.enableInteractions()
        let relay = controller(api)
        await relay.refresh()
        try withChineseSnapshot {
            #expect(NSLocalizedString("Poke", comment: "") == "戳戳")
            #expect(NSLocalizedString("Hug", comment: "") == "抱抱")
            #expect(NSLocalizedString("Peek", comment: "") == "探头")
            let view = PetRelayComposerView(model: PetRelayComposerModel(relay: relay), onClose: {})
                .environment(\.animationsEnabled, false)
            let host = NSHostingView(rootView: view)
            let size = host.fittingSize
            #expect(size.width == 300)
            #expect(size.height > 200 && size.height < 500)
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
                    .write(to: url.appendingPathComponent("paired-interactions.png"))
            }
            #expect(!window.isVisible)
            window.contentView = nil
        }
    }
    /// Explicit opt-in only; uses two throwaway identities, never the real app's
    /// Keychain, preferences, care archive, or message mailbox.
    @Test func liveHTTPSRoundTripWhenExplicitlyEnabled() async throws {
        guard ProcessInfo.processInfo.environment["AGENTPET_RELAY_LIVE_TESTS"] == "1" else { return }
        let api = PetRelayAPI()
        let a = try await api.register(name: "QA Swift A")
        let b = try await api.register(name: "QA Swift B")
        func payload(_ values: [String: String]) throws -> Data { try JSONEncoder().encode(values) }
        let invitation = try await api.fetch("v1/pairing/create", token: a.token, body: Data("{}".utf8))
        let code = try #require(invitation.invitation?.code)
        #expect(PetRelayValidation.validCode(code))
        let waiting = try await api.fetch("v1/pairing/join", token: b.token, body: payload(["code": code.lowercased()]))
        #expect(waiting.pair == nil)
        let paired = try await api.fetch("v1/pairing/confirm", token: a.token, body: payload(["code": code]))
        let pairID = try #require(paired.pair?.id)
        let probe = RelayEventProbe()
        let socket = Task { try await api.watch(token: b.token) { await probe.bump() } }
        defer { socket.cancel() }
        for _ in 0..<100 {
            if await probe.count >= 1 { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        #expect(await probe.count >= 1)
        let clientID = UUID().uuidString
        let text = String(repeating: "👨‍👩‍👧‍👦", count: 20)
        let sent = try await api.fetch("v1/messages", token: a.token, body: payload(["pairID": pairID, "clientID": clientID, "text": text]))
        for _ in 0..<100 {
            if await probe.count >= 2 { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        #expect(await probe.count >= 2)
        _ = try await api.fetch("v1/messages", token: a.token, body: payload(["pairID": pairID, "clientID": clientID, "text": text]))
        let received = try await api.fetch("v1/sync", token: b.token, body: nil)
        #expect(received.incoming.count == 1)
        #expect(received.incoming.first?.text == text)
        let parent = try #require(sent.sent.first?.id)
        let replied = try await api.fetch("v1/messages", token: b.token, body: payload(["pairID": pairID, "clientID": UUID().uuidString, "icon": "heart", "replyTo": parent]))
        #expect(replied.incoming.isEmpty)
        let final = try await api.fetch("v1/sync", token: a.token, body: nil)
        #expect(final.sent.first?.handledAt != nil)
        let replyID = try #require(final.incoming.first?.id)
        struct Ack: Encodable { var ids: [String]; var kind: String }
        _ = try await api.fetch("v1/messages/ack", token: a.token, body: JSONEncoder().encode(Ack(ids: [replyID], kind: "handled")))
        _ = try await api.fetch("v1/pairing/disconnect", token: a.token, body: Data("{}".utf8))
    }

    @Test func isolatedLocalRelayRoundTripSynchronizesBothPetsAndReplies() async throws {
        guard let address = ProcessInfo.processInfo.environment["AGENTPET_RELAY_TEST_URL"],
              let url = URL(string: address), url.host == "127.0.0.1", url.scheme == "http" else { return }
        let api = PetRelayAPI(baseURL: url)
        let profileA = RelayProfileFixture()
        let a = PetRelayController(fileURL: nil, credentials: RelayMockCredential(present: false), api: api, events: false,
                                   profileProvider: { profileA.value })
        let b = PetRelayController(fileURL: nil, credentials: RelayMockCredential(present: false), api: api, events: false,
                                   profileProvider: { PetRelayPetProfile(name: "噜妹", builtinID: "lumei") })
        await a.createInvitation(name: "QA-A")
        let code = try #require(a.mailbox.invitation?.code)
        await b.join(code: code, name: "QA-B")
        await a.refresh()
        await a.confirm()
        await b.refresh()
        #expect(a.pair?.peerPet?.builtinID == "lumei")
        #expect(b.pair?.peerPet?.builtinID == "lulu")
        #expect(a.supportsInteractions && b.supportsInteractions)
        #expect(await a.send(gesture: .poke))
        await b.refresh()
        let message = try #require(b.incoming.first)
        #expect(message.interaction == .poke)
        #expect(message.senderPet?.builtinID == "lulu")
        #expect(b.consumeInteractions(canAnimate: true)?.id == message.id)
        #expect(b.consumeInteractions(canAnimate: true) == nil)
        #expect(b.incoming.count == 1)
        let frame = try #require(PetRelayAppearance.pack(for: profileA.value)?.restingFrames.first)
        let portrait = try #require(PetRelayAppearance.thumbnail(frame))
        profileA.value = PetRelayPetProfile(name: "导入的宠物", thumbnailPNG: portrait)
        await a.refresh()
        await b.refresh()
        #expect(b.pair?.peerPet?.builtinID == nil)
        #expect(b.pair?.peerPet?.thumbnailPNG == portrait)
        #expect(PetRelayAppearance.portrait(for: b.pair?.peerPet) != nil)
        #expect(b.incoming.first?.senderPet?.builtinID == "lulu")
        #expect(await b.send(replyTo: message.id, expectedPairID: message.pairID, gesture: .hug))
        await a.refresh()
        #expect(b.incoming.isEmpty)
        #expect(a.incoming.first?.interaction == .hug)
        #expect(a.mailbox.sent.first?.handledAt != nil)
        await a.disconnect()
        await b.refresh()
        #expect(b.pair == nil)
    }

}
