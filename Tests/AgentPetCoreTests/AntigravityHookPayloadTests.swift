import Testing
import Foundation
@testable import AgentPetCore

@Suite(.serialized)
final class AntigravityHookPayloadTests {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func event(_ json: String) -> AgentEvent? {
        AntigravityHookPayload.decode(from: Data(json.utf8))?.makeEvent(now: now)
    }

    @Test func testPreToolUseIsWorking() {
        let e = event(#"{"conversationId":"c1","workspacePaths":["/Users/me/proj"],"stepIdx":0,"toolCall":{"name":"run_command"}}"#)
        #expect((e?.agentKind) == (.antigravity))
        #expect((e?.sessionId) == ("c1"))
        #expect((e?.eventName) == ("working"))
        #expect((e?.project) == ("/Users/me/proj"))
        #expect(ActivityTheme.chef.running.contains(e?.message ?? ""), Comment(rawValue: "got \(e?.message ?? "nil")"))
        #expect((StateMapper.state(for: .antigravity, eventName: e!.eventName)) == (.working))
    }

    @Test func testDecodesModel() {
        let e = event(#"{"conversationId":"c1","workspacePaths":["/p"],"stepIdx":0,"toolCall":{"name":"run_command"},"model":{"display_name":"Gemini 3 Pro"}}"#)
        #expect((e?.model) == ("Gemini 3 Pro"))
    }

    @Test func testStopWithTerminationReasonIsDone() {
        let e = event(#"{"conversationId":"c2","executionNum":1,"terminationReason":"model_stop","fullyIdle":true}"#)
        #expect((e?.eventName) == ("done"))
        #expect((StateMapper.state(for: .antigravity, eventName: e!.eventName)) == (.done))
    }

    @Test func testStopWithOnlyFullyIdleIsDone() {
        let e = event(#"{"conversationId":"c2","fullyIdle":false}"#)
        #expect((e?.eventName) == ("done"))
    }

    @Test func testPreInvocationIsWorking() {
        let e = event(#"{"conversationId":"c3","invocationNum":2,"initialNumSteps":5}"#)
        #expect((e?.eventName) == ("working"))
    }

    @Test func testPostToolUseIsWorking() {
        let e = event(#"{"conversationId":"c4","stepIdx":3,"error":""}"#)
        #expect((e?.eventName) == ("working"))
    }

    @Test func testMissingConversationIdIsNil() {
        #expect((event(#"{"stepIdx":0,"toolCall":{"name":"x"}}"#)) == nil)
    }

    @Test func testRoutedThroughHookPayloads() {
        let data = Data(#"{"conversationId":"c5","terminationReason":"model_stop"}"#.utf8)
        let e = HookPayload.event(forAgent: .antigravity, stdin: data, now: now)
        #expect((e?.agentKind) == (.antigravity))
        #expect((e?.eventName) == ("done"))
    }
}
