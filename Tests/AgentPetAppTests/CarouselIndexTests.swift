import Testing
import Foundation
@testable import agentpet

@Suite(.serialized)
final class CarouselIndexTests {
    /// A group dropping out leaves `index` past the end; it must still map to
    /// a real page (this was drawn as an empty bubble before).
    @Test func testStaleIndexMapsToExistingPage() {
        #expect((CarouselIndex.shown(1, count: 1)) == (0))
        #expect((CarouselIndex.shown(2, count: 2)) == (0))
        #expect((CarouselIndex.shown(5, count: 3)) == (2))
    }

    @Test func testEmptyCarouselShowsPageZero() {
        #expect((CarouselIndex.shown(3, count: 0)) == (0))
        #expect((CarouselIndex.step(3, by: 1, count: 0)) == (0))
    }

    @Test func testStepWrapsBothWays() {
        #expect((CarouselIndex.step(0, by: 1, count: 3)) == (1))
        #expect((CarouselIndex.step(2, by: 1, count: 3)) == (0))
        #expect((CarouselIndex.step(0, by: -1, count: 3)) == (2))
    }

    /// Stepping with the live count after a shrink stays in range, whatever
    /// the stale index was.
    @Test func testStepAfterShrinkStaysInRange() {
        for stale in 0..<6 {
            let next = CarouselIndex.step(stale, by: 1, count: 1)
            #expect((next) == (0), Comment(rawValue: "stale index \(stale)"))
        }
    }
}
