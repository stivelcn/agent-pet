import Testing
import Foundation
@testable import AgentPetCore

@Suite(.serialized)
final class ProjectPetResolverTests {
    private let cat = ProjectPetMapping(projectPath: "/work/foo", petID: "cat")
    private let dog = ProjectPetMapping(projectPath: "/work/foo/api", petID: "dog")

    @Test func testExactMatch() {
        #expect((ProjectPetResolver.mapping(forProject: "/work/foo", mappings: [cat])?.petID) == ("cat"))
    }
    @Test func testSubfolderMatches() {
        #expect((ProjectPetResolver.mapping(forProject: "/work/foo/src", mappings: [cat])?.petID) == ("cat"))
    }
    @Test func testLongestMatchWins() {
        #expect((ProjectPetResolver.mapping(forProject: "/work/foo/api/v1", mappings: [cat, dog])?.petID) == ("dog"))
    }
    @Test func testDirectoryBoundaryNotPrefixString() {
        // "/work/foobar" must NOT match "/work/foo"
        #expect((ProjectPetResolver.mapping(forProject: "/work/foobar", mappings: [cat])) == nil)
    }
    @Test func testTrailingSlashNormalized() {
        #expect((ProjectPetResolver.mapping(forProject: "/work/foo/", mappings: [cat])?.petID) == ("cat"))
        let catSlash = ProjectPetMapping(projectPath: "/work/foo/", petID: "cat")
        #expect((ProjectPetResolver.mapping(forProject: "/work/foo", mappings: [catSlash])?.petID) == ("cat"))
    }
    @Test func testNilOrEmptyCwdReturnsNil() {
        #expect((ProjectPetResolver.mapping(forProject: nil, mappings: [cat])) == nil)
        #expect((ProjectPetResolver.mapping(forProject: "", mappings: [cat])) == nil)
    }
    @Test func testNoMatchReturnsNil() {
        #expect((ProjectPetResolver.mapping(forProject: "/other", mappings: [cat])) == nil)
    }
}
