import AgentPetCore
import Testing
import Foundation
@testable import agentpet

@MainActor
@Suite(.serialized)
final class BubbleSettingsTests {
    private let multiAgentBubbleKey = "agentpet.bubble.multiAgentBubbleEnabled"
    private let sessionGroupingKey = "agentpet.bubble.sessionGrouping"
    private let collapseDuplicatesKey = "agentpet.bubble.collapseDuplicates"

    private func setUp() {

        LocalPreferences.defaults.removeObject(forKey: multiAgentBubbleKey)
        LocalPreferences.defaults.removeObject(forKey: sessionGroupingKey)
        LocalPreferences.defaults.removeObject(forKey: collapseDuplicatesKey)
    }

    private func tearDown() {
        LocalPreferences.defaults.removeObject(forKey: multiAgentBubbleKey)
        LocalPreferences.defaults.removeObject(forKey: sessionGroupingKey)
        LocalPreferences.defaults.removeObject(forKey: collapseDuplicatesKey)

    }

    @Test func testMultiAgentBubbleDefaultsOn() {
        setUp()
        defer { tearDown() }
        let settings = BubbleSettings()

        #expect(settings.multiAgentBubbleEnabled)
    }

    @Test func testMultiAgentBubblePersists() {
        setUp()
        defer { tearDown() }
        let settings = BubbleSettings()

        settings.multiAgentBubbleEnabled = true

        #expect(BubbleSettings().multiAgentBubbleEnabled)
    }

    @Test func testSessionGroupingDefaultsToByKind() {
        setUp()
        defer { tearDown() }
        #expect((BubbleSettings().sessionGrouping) == (.byKind))
    }

    @Test func testSessionGroupingPersists() {
        setUp()
        defer { tearDown() }
        let settings = BubbleSettings()
        settings.sessionGrouping = .allSessions
        #expect((BubbleSettings().sessionGrouping) == (.allSessions))
    }

    @Test func testSessionGroupingMigratesFromLegacyCollapseOff() {
        setUp()
        defer { tearDown() }
        LocalPreferences.defaults.set(false, forKey: collapseDuplicatesKey)
        #expect((BubbleSettings().sessionGrouping) == (.allSessions))
    }

    @Test func testModelTokenExistsAndHasMetadata() {
        setUp()
        defer { tearDown() }
        #expect(BubbleToken.allCases.contains(.model))
        #expect((BubbleToken.model.shortName) == ("Model"))
        #expect((BubbleToken.model.chipSymbol) == ("cpu"))
    }

    @Test func testModelTokenVisibilityInPresets() {
        setUp()
        defer { tearDown() }
        func isVisible(_ layout: BubbleLayout) -> Bool? {
            layout.tokens.first { $0.token == .model }?.isVisible
        }
        #expect((isVisible(.original)) == (false))
        #expect((isVisible(.standard)) == (false))
        #expect((isVisible(.detailed)) == (true))
    }
}
