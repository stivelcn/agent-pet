import Foundation
import Testing
@testable import AgentPetCore

struct PetRelayTests {
    private func message(_ id: String = "m1", pair: String = "pair1", text: String = "你好") -> PetRelayMessage {
        PetRelayMessage(id: id, clientID: "client-" + id, pairID: pair, senderName: "噜噜", text: text, createdAt: 1)
    }
    private func snapshot(_ messages: [PetRelayMessage] = [], pair: String? = "pair1") -> PetRelaySnapshot {
        PetRelaySnapshot(deviceID: "device1", name: "噜妹", pair: pair.map { PetRelayPair(id: $0, peerName: "噜噜") }, incoming: messages)
    }
    @Test func pairingCodeRequiresSixASCIICharactersWithBothLettersAndDigits() {
        for valid in ["a12b3c", " A12b3C\n", "00000z", "zZzZz1"] { #expect(PetRelayValidation.validCode(valid)) }
        for invalid in ["123456", "abcdef", "A1234", "A123456", "Ａ12345", "a12-45", "a12 45", "a12💧45"] {
            #expect(!PetRelayValidation.validCode(invalid))
        }
        #expect(PetRelayValidation.normalizedCode(" a12b3c ") == "A12B3C")
    }
    @Test func twentyCharactersMeansGraphemesIncludingChineseAndJoinedEmoji() {
        #expect(PetRelayValidation.validText(String(repeating: "你", count: 20)))
        #expect(PetRelayValidation.validText(String(repeating: "👨‍👩‍👧‍👦", count: 20)))
        #expect(PetRelayValidation.validText(String(repeating: "e\u{301}", count: 20)))
        #expect(!PetRelayValidation.validText(String(repeating: "你", count: 21)))
        #expect(!PetRelayValidation.validText("a\nb"))
        #expect(!PetRelayValidation.validText("a\u{0}b"))
        #expect(!PetRelayValidation.validText(" \n "))
    }
    @Test func snapshotsQueueRatherThanOverwriteUnreadMessages() {
        var box = PetRelayMailbox()
        box.merge(snapshot([message()]))
        box.merge(snapshot([message("m2")]))
        box.merge(snapshot([message("m2")]))
        #expect(box.incoming.map(\.id) == ["m1", "m2"])
        #expect(box.delivered == ["m1", "m2"])
    }
    @Test func unpairAndNewPairCannotSilentlyClearUnreadOrRetargetOutbox() {
        var box = PetRelayMailbox()
        box.merge(snapshot([message()]))
        box.outbox.append(PetRelayDraft(pairID: "pair1", text: "等一下"))
        box.merge(snapshot(pair: nil))
        box.merge(snapshot(pair: "pair2"))
        #expect(box.incoming.count == 1)
        #expect(box.outbox[0].pairID == "pair1")
        #expect(box.pair?.id == "pair2")
    }
    @Test func dismissalTombstoneStopsStaleSnapshotResurrection() {
        var box = PetRelayMailbox()
        box.merge(snapshot([message()]))
        box.dismiss("m1")
        box.merge(snapshot([message()]))
        #expect(box.incoming.isEmpty)
        #expect(box.handled.contains("m1"))
    }
    @Test func unacceptedOrCancelledReplyKeepsParentButAcceptedReplyClearsOnlyParent() {
        var box = PetRelayMailbox()
        box.merge(snapshot([message(), message("m2")]))
        let draft = PetRelayDraft(pairID: "pair1", text: "收到", replyTo: "m1")
        box.outbox.append(draft)
        #expect(box.incoming.count == 2)
        box.accept("unknown-send")
        #expect(box.incoming.count == 2)
        box.accept(draft.id)
        #expect(box.incoming.map(\.id) == ["m2"])
        #expect(box.handled.contains("m1"))
    }
    @Test func lostHTTPResponseIsReconciledByStableClientID() {
        var box = PetRelayMailbox()
        box.merge(snapshot([message()]))
        let draft = PetRelayDraft(pairID: "pair1", icon: .heart, replyTo: "m1")
        box.outbox.append(draft)
        var result = snapshot()
        result.sent = [PetRelayMessage(id: "server1", clientID: draft.id, pairID: "pair1", senderName: "噜妹", icon: .heart, createdAt: 2)]
        box.merge(result)
        #expect(box.outbox.isEmpty)
        #expect(box.incoming.isEmpty)
    }
    @Test func mailboxRestartRetainsInboxAckQueueAndOriginalDraftIdentity() throws {
        var box = PetRelayMailbox()
        box.merge(snapshot([message(), message("m2")]))
        box.dismiss("m1")
        box.outbox.append(PetRelayDraft(pairID: "pair1", text: "你好"))
        let restarted = try JSONDecoder().decode(PetRelayMailbox.self, from: JSONEncoder().encode(box))
        #expect(restarted == box)
    }
    @Test func anotherInstallationCannotReplaceMailbox() {
        var box = PetRelayMailbox()
        box.merge(snapshot([message()]))
        box.merge(PetRelaySnapshot(deviceID: "stranger", name: "No"))
        #expect(box.deviceID == "device1")
        #expect(box.incoming.count == 1)
    }
    @Test func presetIconsHaveStableProtocolIDsAndSymbols() {
        #expect(PetRelayIcon.allCases.count == 6)
        #expect(PetRelayIcon.water.symbol == "💧")
        #expect(PetRelayIcon.heart.rawValue == "heart")
        #expect(Set(PetRelayIcon.allCases.map(\.labelKey)).count == 6)
    }
}
