import Foundation
import Testing
@testable import AgentPetCore

struct PetTogetherTests {
    private func session(_ mode: PetTogetherMode = .visit, status: String = "active") -> PetTogetherSession {
        PetTogetherSession(id: "t1", clientID: "client1", pairID: "p1", initiatorID: "a",
            mode: mode, status: status, createdAt: 90, startedAt: status == "active" ? 100 : nil,
            expiresAt: mode == .visit ? 400 : 1900, restAt: mode == .work ? 1600 : nil)
    }
    @Test func visitorsLeaveTheirOwnNestAndOnlyTheHostShowsTwoPets() {
        let visit = session()
        #expect(visit.isAway(deviceID: "a", at: 101))
        #expect(!visit.isAway(deviceID: "b", at: 101))
        #expect(!visit.showsCompanion(deviceID: "a", at: 101))
        #expect(visit.showsCompanion(deviceID: "b", at: 101))
        for id in ["a", "b"] {
            #expect(!visit.isAway(deviceID: id, at: 400))
            #expect(!visit.showsCompanion(deviceID: id, at: 400))
        }
        #expect(!session(status: "pending").isActive(at: 101))
        #expect(session(status: "pending").isPending(at: 101))
        #expect(!session(status: "ended").isActive(at: 101))
    }
    @Test func workingTogetherShowsBothPetsAndSharesTheSameTeaBreakDeadline() {
        let work = session(.work)
        for id in ["a", "b"] {
            #expect(work.showsCompanion(deviceID: id, at: 101))
            #expect(!work.isAway(deviceID: id, at: 101))
        }
        #expect(!work.isResting(at: 1599))
        #expect(work.isResting(at: 1600))
        #expect(!work.isResting(at: 1900))
    }
    @Test func sharedActivityRoundTripsAndAnOmittedOrDifferentPairClearsOnlyTheActivity() throws {
        var box = PetRelayMailbox()
        let message = PetRelayMessage(id: "unread", clientID: "m1", pairID: "p1", senderName: "朋友", text: "你好", createdAt: 1)
        box.merge(PetRelaySnapshot(deviceID: "a", name: "我", pair: PetRelayPair(id: "p1", peerName: "朋友"),
            incoming: [message], together: session()))
        #expect(try JSONDecoder().decode(PetRelayMailbox.self, from: JSONEncoder().encode(box)) == box)
        box.pendingTogether = PetTogetherCommand(pairID: "p1", sessionID: "t1", action: "end", createdAt: 101)
        box.merge(PetRelaySnapshot(deviceID: "a", name: "我"))
        #expect(box.together == nil && box.pendingTogether == nil)
        #expect(box.incoming == [message] && box.handled.isEmpty)
        box.merge(PetRelaySnapshot(deviceID: "a", name: "我", pair: PetRelayPair(id: "p2", peerName: "新朋友"), together: session()))
        #expect(box.together == nil && box.incoming == [message])
    }
    @Test func stopCommandsRemainDurableWhileOldInvitationsCannotRetryForever() throws {
        let invite = PetTogetherCommand(pairID: "p1", mode: .visit, createdAt: 100)
        #expect(!invite.isExpired(at: 219) && invite.isExpired(at: 220))
        for action in ["end", "decline", "cancel"] {
            let command = PetTogetherCommand(pairID: "p1", sessionID: "t1", action: action, createdAt: 100)
            #expect(command.stopsPresentation && !command.isExpired(at: 100_000))
            #expect(try JSONDecoder().decode(PetTogetherCommand.self, from: JSONEncoder().encode(command)) == command)
        }
    }
    @Test func oldSnapshotsAndPetProfilesDecodeWithoutEnablingTogether() throws {
        let old = Data(#"{"deviceID":"a","name":"我","incoming":[],"sent":[]}"#.utf8)
        let snapshot = try JSONDecoder().decode(PetRelaySnapshot.self, from: old)
        #expect(snapshot.together == nil && snapshot.serverTime == nil)
        let profile = try JSONDecoder().decode(PetRelayPetProfile.self,
            from: Data(#"{"name":"噜噜","builtinID":"lulu","interactionVersion":1}"#.utf8))
        #expect(profile.togetherVersion == nil)
    }
}
