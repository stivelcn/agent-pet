import Testing
import Foundation
@testable import AgentPetCore

@Suite(.serialized)
final class AgentEventTests {
    private let now = Date(timeIntervalSince1970: 1_000_000)

    @Test func testApprovalFieldsDefaultToNil() {
        let event = AgentEvent(sessionId: "s1", agentKind: .claude, eventName: "Stop", timestamp: now)
        #expect((event.approvalRequestId) == nil)
        #expect((event.toolName) == nil)
        #expect((event.toolSummary) == nil)
    }

    @Test func testCodableRoundTripPreservesApprovalFields() throws {
        let event = AgentEvent(
            sessionId: "s1", agentKind: .claude, eventName: "PreToolUse",
            approvalRequestId: "req-1", toolName: "Bash", toolSummary: "npm test",
            timestamp: now
        )
        let data = try EventCoding.encoder.encode(event)
        let decoded = try EventCoding.decoder.decode(AgentEvent.self, from: data)
        #expect((decoded) == (event))
        #expect((decoded.approvalRequestId) == ("req-1"))
        #expect((decoded.toolName) == ("Bash"))
        #expect((decoded.toolSummary) == ("npm test"))
    }

    @Test func testCodableRoundTripWithNilApprovalFields() throws {
        let event = AgentEvent(sessionId: "s1", agentKind: .claude, eventName: "Stop", timestamp: now)
        let data = try EventCoding.encoder.encode(event)
        let decoded = try EventCoding.decoder.decode(AgentEvent.self, from: data)
        #expect((decoded) == (event))
        #expect((decoded.approvalRequestId) == nil)
        #expect((decoded.toolName) == nil)
        #expect((decoded.toolSummary) == nil)
    }
}
