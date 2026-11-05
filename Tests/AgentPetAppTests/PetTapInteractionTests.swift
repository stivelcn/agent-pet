import Foundation
import Testing
@testable import agentpet

@MainActor
@Suite(.serialized)
struct PetTapInteractionTests {
    @Test func pairedTapOpensTheClickedPetsComposer() {
        let model = PetWindowModel(key: "/project/example")
        #expect(model.tapDestination(wasDrag: false, paired: true) == .composer("/project/example"))
    }
    @Test func unpairedTapOpensPairingSettings() {
        #expect(PetWindowModel(key: "default").tapDestination(wasDrag: false, paired: false) == .pairing)
    }
    @Test func draggingNeverOpensMessagingOrPairing() {
        let model = PetWindowModel(key: "default")
        for paired in [true, false] { #expect(model.tapDestination(wasDrag: true, paired: paired) == .none) }
    }
    @Test func repeatedTapsDoNotNeedReactionTimersOrCooldowns() {
        let model = PetWindowModel(key: "default")
        for _ in 0..<20 { #expect(model.tapDestination(wasDrag: false, paired: true) == .composer("default")) }
        #expect(model.chatLine.isEmpty)
    }
}
