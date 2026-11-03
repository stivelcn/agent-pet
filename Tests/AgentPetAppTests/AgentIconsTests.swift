import Testing
import Foundation
@testable import agentpet

@MainActor
@Suite(.serialized)
final class AgentIconsTests {
    /// Every kind offered in the brand-logo picker must actually decode to an
    /// image; a kind listed there without artwork would show a blank cell.
    @Test func testEveryBrandKindHasAnImage() {
        for kind in AgentIcons.brandKinds {
            #expect((AgentIcons.image(for: kind)) != nil, Comment(rawValue: "\(kind.rawValue) has no brand image"))
        }
    }

    @Test func testJcodeLogoDecodesAtEmbeddedSize() throws {
        let img = try #require(AgentIcons.image(for: .jcode))
        let rep = try #require(img.representations.first)
        #expect((rep.pixelsWide) == (64))
        #expect((rep.pixelsHigh) == (64))
    }
}
