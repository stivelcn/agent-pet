import Foundation
import Testing
import AgentPetCore
@testable import agentpet

struct PetMessageExpansionTests {
    private func message(_ id: String, at time: Double) -> PetRelayMessage {
        PetRelayMessage(id: id, clientID: id, pairID: "pair", senderName: "噜噜", text: "完整消息 " + id, createdAt: time)
    }
    @Test func expandedMessagesAreChronologicalWithStableTieBreaking() {
        let state = PetMessageExpansion()
        let ordered = state.ordered([message("c", at: 2), message("b", at: 1), message("a", at: 1)])
        #expect(ordered.map(\.id) == ["a", "b", "c"])
        #expect(ordered.map(\.content) == ["完整消息 a", "完整消息 b", "完整消息 c"])
    }
    @Test func expandingAndCollapsingNeverAcknowledgesOrDeletesMessages() {
        var mailbox = PetRelayMailbox()
        mailbox.incoming = [message("a", at: 1), message("b", at: 2)]
        let original = mailbox
        var state = PetMessageExpansion()
        #expect(!state.isExpanded)
        state.toggle()
        #expect(state.isExpanded)
        #expect(state.ordered(mailbox.incoming).count == 2)
        state.toggle()
        #expect(!state.isExpanded)
        #expect(mailbox == original)
    }
    @Test func newMessagesAppearWithoutCollapsingAndIndividualActionsKeepTheRest() {
        var mailbox = PetRelayMailbox()
        mailbox.incoming = [message("b", at: 2)]
        var state = PetMessageExpansion()
        state.toggle()
        mailbox.incoming += [message("c", at: 3), message("a", at: 1)]
        #expect(state.isExpanded)
        #expect(state.ordered(mailbox.incoming).map(\.id) == ["a", "b", "c"])
        mailbox.dismiss("b")
        #expect(state.ordered(mailbox.incoming).map(\.id) == ["a", "c"])
        #expect(mailbox.handled == ["b"])
    }
}
