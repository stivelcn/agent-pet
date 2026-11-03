import Testing
import Foundation
@testable import AgentPetCore

@Suite(.serialized)
final class ProjectNamesTests {
    @Test func testFolderNameIsLastComponentAndWholePathForRoot() {
        #expect((ProjectNames.folderName("/Users/me/Projects/helm-claw")) == ("helm-claw"))
        #expect((ProjectNames.folderName("/")) == ("/"))
    }

    @Test func testLabelFallsBackToFolderWhenNoOrBlankName() {
        let path = "/Users/me/Projects"
        #expect((ProjectNames.label(for: path, names: [:])) == ("Projects"))
        #expect((ProjectNames.label(for: path, names: [ProjectNames.id(for: path): ""])) == ("Projects"))
    }

    @Test func testLabelUsesCustomNameKeyedByPathId() {
        let path = "/Users/me/Projects"
        let names = [ProjectNames.id(for: path): "Scratch"]
        #expect((ProjectNames.label(for: path, names: names)) == ("Scratch"))
        // A different folder with the same last component is a different project.
        #expect((ProjectNames.label(for: "/tmp/Projects", names: names)) == ("Projects"))
    }

    @Test func testCleanTrimsAndCaps() {
        #expect((ProjectNames.clean("  hello \n")) == ("hello"))
        #expect((ProjectNames.clean("   ")) == (""))
        #expect((ProjectNames.clean(String(repeating: "x", count: 100)).count) == (ProjectNames.maxLength))
    }

    /// The id must equal what the usage store (and the Windows app) compute, or a
    /// name set from the usage-derived project list would never match a session.
    @Test func testIdMatchesKnownFnv1aVectors() {
        // FNV-1a 32-bit of "" and "a" (public test vectors), prefixed with "p".
        #expect((ProjectNames.id(for: "")) == ("p811c9dc5"))
        #expect((ProjectNames.id(for: "a")) == ("pe40c292c"))
    }

    @Test func testTickerLineUsesCustomName() {
        let path = "/Users/me/Projects"
        let s = AgentSession(id: "s1", agentKind: .jcode, project: path, state: .working,
                             message: "hi", source: .hook, updatedAt: Date(timeIntervalSince1970: 0))
        #expect((TickerFormatter.line(for: s)) == ("jcode [Projects] → hi"))
        #expect((TickerFormatter.line(for: s, projectNames: [ProjectNames.id(for: path): "Scratch"])) == ("jcode [Scratch] → hi"))
    }
}
