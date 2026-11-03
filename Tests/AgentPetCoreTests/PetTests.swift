import Testing
import Foundation
@testable import AgentPetCore

@Suite(.serialized)
final class MoodResolverTests {
    private func session(_ state: AgentState, id: String) -> AgentSession {
        AgentSession(id: id, agentKind: .claude, state: state, source: .hook,
                     updatedAt: Date(timeIntervalSince1970: 0))
    }

    @Test func testEmptyIsIdle() {
        #expect((MoodResolver.aggregate([])) == (.idle))
    }

    @Test func testWorkingWins() {
        let sessions = [session(.working, id: "a"), session(.waiting, id: "b"), session(.done, id: "c")]
        #expect((MoodResolver.aggregate(sessions)) == (.working), Comment(rawValue: "running work is prioritised"))
    }

    @Test func testWaitingBeatsDone() {
        #expect((MoodResolver.aggregate([session(.done, id: "a"), session(.waiting, id: "b")])) == (.waiting))
    }

    @Test func testRegisteredIsNotWorking() {
        // An agent that is merely open (registered) but not doing anything keeps
        // the pet idle, not "working".
        #expect((MoodResolver.aggregate([session(.registered, id: "a")])) == (.idle))
        #expect((MoodResolver.aggregate([session(.registered, id: "a"), session(.working, id: "b")])) == (.working))
    }

    @Test func testDoneOnly() {
        #expect((MoodResolver.aggregate([session(.done, id: "a"), session(.idle, id: "b")])) == (.done))
    }
}
