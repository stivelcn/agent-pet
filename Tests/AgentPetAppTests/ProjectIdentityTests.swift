import Testing
import Foundation
import AgentPetCore
@testable import agentpet

/// Custom names are looked up by `ProjectNames.id`, usage rows are stored under
/// `ProjectUsageStore.projectIdentity`. They must always agree, or a name set from
/// the usage-derived Settings list would silently stop matching its project.
@MainActor
@Suite(.serialized)
final class ProjectIdentityTests {
    @Test func testUsageIdentityUsesTheSameIdAsProjectNames() {
        let paths = ["", "/", "/Users/me/Projects", "/Users/me/Dự án/ứng dụng", "/tmp/日本語/プロジェクト",
                     "/tmp/emoji 🐉/x", String(repeating: "/a", count: 200)]
        for p in paths {
            #expect((ProjectUsageStore.projectIdentity(p).id) == (ProjectNames.id(for: p)), Comment(rawValue: p))
        }
    }

    @Test func testUsageIdentityNameIsTheFolderCappedAtSixty() {
        #expect((ProjectUsageStore.projectIdentity("/Users/me/helm-claw").name) == ("helm-claw"))
        #expect((ProjectUsageStore.projectIdentity("/").name) == ("/"))
        let long = "/x/" + String(repeating: "n", count: 100)
        #expect((ProjectUsageStore.projectIdentity(long).name.count) == (60))
    }
}
