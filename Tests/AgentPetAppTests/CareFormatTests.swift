import Testing
import Foundation
import AgentPetCore
@testable import agentpet

@Suite(.serialized)
final class CareFormatTests {
    @Test func testTokensAreCompactAtEachMagnitude() {
        #expect((CareFormat.tokens(0)) == ("0"))
        #expect((CareFormat.tokens(999)) == ("999"))
        #expect((CareFormat.tokens(1_000)) == ("1k"))
        #expect((CareFormat.tokens(12_345)) == ("12k"))
        #expect((CareFormat.tokens(1_000_000)) == ("1.0M"))
        #expect((CareFormat.tokens(2_540_000)) == ("2.5M"))
    }

    @Test func testHungerHasADistinctLabelForEveryCase() {
        let labels = PetHunger.allCases.map(CareFormat.hunger)
        #expect((labels) == (["Full", "Satisfied", "Peckish", "Hungry", "Starving"]))
        #expect((Set(labels).count) == (PetHunger.allCases.count))
    }

    @Test func testPlainKeepsEveryDigit() {
        #expect((CareFormat.plain(0)) == ("0"))
        let digits = CareFormat.plain(1_234_567).filter(\.isNumber)
        #expect((digits) == ("1234567"))
    }
}
