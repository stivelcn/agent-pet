import Testing
import Foundation
@testable import AgentPetCore

@Suite(.serialized)
final class AgentCatalogTests {
    @Test func testHookAgentsSupported() {
        let byKind = Dictionary(uniqueKeysWithValues: AgentCatalog.all.map { ($0.kind, $0) })
        #expect((byKind[.claude]?.isSupported) == (true))
        #expect((byKind[.codex]?.isSupported) == (true))
        #expect((byKind[.gemini]?.isSupported) == (true))
    }
}
