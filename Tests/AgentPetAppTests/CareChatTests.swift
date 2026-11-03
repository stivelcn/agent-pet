import Testing
import Foundation
@testable import agentpet
import AgentPetCore

@MainActor
@Suite(.serialized)
final class CareChatTests {

    private let basePhrases = ["Hello!", "Hi there!"]

    @Test func testIdlePoolFullHungerNoHungryLines() {
        let pool = CareChat.idlePool(base: basePhrases, hunger: .full)
        // Should not contain any hungry/starving care lines
        let careLines = Set(CareChat.hungry + CareChat.starving)
        for line in pool {
            #expect(!(careLines.contains(line)), Comment(rawValue: "Pool should not contain care line: \(line)"))
        }
        // Base phrases should still be present
        #expect(pool.contains("Hello!"))
    }

    @Test func testIdlePoolHungryAddsHungryLines() {
        let pool = CareChat.idlePool(base: basePhrases, hunger: .hungry)
        // Pool should include base phrases AND hungry care lines
        #expect(pool.count > basePhrases.count)
        #expect(pool.contains("Hello!"))
    }

    @Test func testIdlePoolStarvingReplacesPool() {
        let pool = CareChat.idlePool(base: basePhrases, hunger: .starving)
        // Starving replaces the entire pool — base phrases should be gone
        #expect(!(pool.contains("Hello!")))
        #expect(!(pool.isEmpty))
    }
}
