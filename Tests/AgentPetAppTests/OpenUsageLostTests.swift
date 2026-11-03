import Testing
import Foundation
@testable import agentpet

/// The Care tab warns only when OpenUsage answered earlier and has then missed
/// two polls in a row. Never having seen it must stay silent (most people
/// don't run it), and one slow answer must not raise a false alarm.
@Suite(.serialized)
final class OpenUsageLostTests {
    @Test func testNeverSeenStaysSilentHoweverManyMisses() {
        #expect(!(OpenUsageClient.isLost(missedPolls: 0, everSeen: false)))
        #expect(!(OpenUsageClient.isLost(missedPolls: 5, everSeen: false)))
    }

    @Test func testOneMissAfterSeenIsNotLostYet() {
        #expect(!(OpenUsageClient.isLost(missedPolls: 1, everSeen: true)))
    }

    @Test func testTwoMissesInARowAfterSeenIsLost() {
        #expect(OpenUsageClient.isLost(missedPolls: 2, everSeen: true))
        #expect(OpenUsageClient.isLost(missedPolls: 7, everSeen: true))
    }

    @Test func testReachableIsNotLost() {
        #expect(!(OpenUsageClient.isLost(missedPolls: 0, everSeen: true)))
    }
}
