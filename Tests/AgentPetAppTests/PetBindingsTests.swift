import Testing
import Foundation
@testable import agentpet
@testable import AgentPetCore

@Suite(.serialized)
final class PetBindingsTests {
    @Test func testDefaultsIncludeNewMoods() {
        let b = PetBindings.defaults(clipCount: 9)
        #expect((b.byMood[PetMood.sleepy.rawValue]) != nil, Comment(rawValue: "sleepy must get a default clip"))
        #expect((b.byMood[PetMood.levelup.rawValue]) != nil, Comment(rawValue: "levelup must get a default clip"))
    }

    @Test func testDefaultsClampWithinClipBounds() {
        let count = 3
        let b = PetBindings.defaults(clipCount: count)
        for mood in PetMood.allCases {
            let idx = b.clipIndex(for: mood)
            #expect((idx) >= (0))
            #expect((idx) <= (count - 1), Comment(rawValue: "\(mood) clip index must stay within clip bounds"))
        }
    }

    @Test func testZeroClipsYieldsZeroIndex() {
        let b = PetBindings.defaults(clipCount: 0)
        for mood in PetMood.allCases {
            #expect((b.clipIndex(for: mood)) == (0), Comment(rawValue: "\(mood) must fall back to clip 0 with no clips"))
        }
    }
}
