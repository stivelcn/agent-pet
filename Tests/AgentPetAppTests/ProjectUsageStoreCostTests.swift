import AgentPetCore
import Testing
import Foundation
@testable import agentpet

@MainActor
@Suite(.serialized)
final class ProjectUsageStoreCostTests {
    nonisolated(unsafe) private var suite = ""
    nonisolated(unsafe) private var defaults: UserDefaults!

    private func setUp() {

        suite = "local.agentpet.tests.projectUsage." + UUID().uuidString
        defaults = UserDefaults(suiteName: suite)!
    }

    private func tearDown() {
        defaults.removePersistentDomain(forName: suite)
        defaults = nil

    }

    // a) Backward-compat decode: old JSON without costUSD must still decode, defaulting to 0.
    @Test func testRowDecodesOldFormatWithoutCostUSD() throws {
        setUp()
        defer { tearDown() }
        let json = """
        {"projectId":"p1","projectName":"test","agent":"claude","day":"2026-07-01","tokens":100,"sessions":1}
        """
        let data = Data(json.utf8)
        let row = try JSONDecoder().decode(ProjectUsageStore.Row.self, from: data)
        #expect((row.costUSD) == (0))
        #expect((row.tokens) == (100))
    }

    // b) Forward decode: JSON with costUSD present decodes correctly.
    @Test func testRowDecodesNewFormatWithCostUSD() throws {
        setUp()
        defer { tearDown() }
        let json = """
        {"projectId":"p1","projectName":"test","agent":"claude","day":"2026-07-01","tokens":100,"sessions":1,"costUSD":1.5}
        """
        let data = Data(json.utf8)
        let row = try JSONDecoder().decode(ProjectUsageStore.Row.self, from: data)
        #expect((row.costUSD) == (1.5))
    }

    // c) recordTokens with cost accumulates correctly across multiple calls.
    @Test func testRecordTokensAccumulatesCost() {
        setUp()
        defer { tearDown() }
        let store = ProjectUsageStore(defaults: defaults)
        store.recordTokens(1000, project: "/some/project", agent: "claude", costUSD: 0.05)
        store.recordTokens(1000, project: "/some/project", agent: "claude", costUSD: 0.05)

        let row = store.recordedRows().first { $0.agent == "claude" }
        #expect((row) != nil)
        #expect((row?.tokens) == (2000))
        #expect(abs((row?.costUSD ?? -1) - (0.10)) <= 0.0001)
    }

    // d) recordTokens without cost arg defaults to 0, keeping existing call sites intact.
    @Test func testRecordTokensWithoutCostDefaultsToZero() {
        setUp()
        defer { tearDown() }
        let store = ProjectUsageStore(defaults: defaults)
        store.recordTokens(500, project: "/p", agent: "claude")

        let row = store.recordedRows().first { $0.agent == "claude" }
        #expect((row) != nil)
        #expect((row?.costUSD) == (0))
    }

    // e) todayCostUSD sums today's rows across projects/agents.
    @Test func testTodayCostUSDSumsAcrossProjects() {
        setUp()
        defer { tearDown() }
        let store = ProjectUsageStore(defaults: defaults)
        store.recordTokens(1000, project: "/project/one", agent: "claude", costUSD: 0.10)
        store.recordTokens(2000, project: "/project/two", agent: "codex", costUSD: 0.20)

        #expect(abs((store.todayCostUSD) - (0.30)) <= 0.0001)
    }

    // f) monthlyCostUSD is at least todayCostUSD, and both are non-negative.
    @Test func testMonthlyCostUSDIsAtLeastTodayCostUSD() {
        setUp()
        defer { tearDown() }
        let store = ProjectUsageStore(defaults: defaults)
        store.recordTokens(1000, project: "/project/one", agent: "claude", costUSD: 0.10)

        #expect((store.monthlyCostUSD) >= (store.todayCostUSD))
        #expect((store.todayCostUSD) >= (0))
        #expect((store.monthlyCostUSD) >= (0))
    }
    @Test func testLocalUsageSurvivesReloadWithoutCloud() {
        setUp()
        defer { tearDown() }
        let store = ProjectUsageStore(defaults: defaults)
        // Explicitly synthetic, isolated unit-test data; never real usage records.
        store.recordTokens(300, project: "/synthetic/project", agent: "claude", costUSD: 0.02)
        store.recordSession(project: "/synthetic/project", agent: "claude")
        let expected = store.recordedRows()

        let restored = ProjectUsageStore(defaults: defaults)
        #expect((restored.recordedRows()) == (expected))
        #expect((restored.recordedRows().first?.tokens) == (300))
        #expect((restored.recordedRows().first?.sessions) == (1))
        #expect(abs((restored.todayCostUSD) - (0.02)) <= 0.0001)
    }

}
