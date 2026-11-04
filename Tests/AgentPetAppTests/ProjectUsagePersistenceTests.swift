import Foundation
import Testing
@testable import agentpet

@MainActor
@Suite(.serialized)
struct ProjectUsagePersistenceTests {
    private func withDefaults(_ body: (UserDefaults) throws -> Void) rethrows {
        let suite = "local.agentpet.tests.tokens.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        try body(defaults)
    }

    @Test func legacyRowsDecodeWithOrWithoutRetiredFields() throws {
        // Explicitly synthetic compatibility fixtures, never real usage records.
        for extra in ["", ",\"costUSD\":1.5"] {
            let json = #"{"projectId":"p1","projectName":"synthetic","agent":"claude","day":"2026-07-01","tokens":100,"sessions":1\#(extra)}"#
            let row = try JSONDecoder().decode(ProjectUsageStore.Row.self, from: Data(json.utf8))
            #expect(row.tokens == 100)
            #expect(row.sessions == 1)
            #expect(row.day == "2026-07-01")
            let data = try JSONEncoder().encode(row)
            let encoded = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
            #expect(Set(encoded.keys) == ["projectId", "projectName", "agent", "day", "tokens", "sessions"])
        }
    }

    @Test func legacyLedgerSurvivesAppendAndReloadWithOnlyTokenFields() throws {
        try withDefaults { defaults in
            let project = "/synthetic/project"
            let id = ProjectUsageStore.projectIdentity(project).id
            let json = #"{"\#(id)|claude|2026-07-01":{"projectId":"\#(id)","projectName":"project","agent":"claude","day":"2026-07-01","tokens":100,"sessions":1,"costUSD":1.5}}"#
            defaults.set(Data(json.utf8), forKey: "agentpet.projectUsage")
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(secondsFromGMT: 0)!
            let now = ISO8601DateFormatter().date(from: "2026-07-01T12:00:00Z")!
            let store = ProjectUsageStore(defaults: defaults, now: { now }, calendar: calendar)
            #expect(store.recordedRows().first?.tokens == 100)
            store.recordTokens(300, project: project, agent: "claude")
            store.recordSession(project: project, agent: "claude")
            let restored = ProjectUsageStore(defaults: defaults, now: { now }, calendar: calendar)
            #expect(restored.recordedRows() == store.recordedRows())
            #expect(restored.recordedRows().count == 1)
            #expect(restored.recordedRows().first?.tokens == 400)
            #expect(restored.recordedRows().first?.sessions == 2)
            let data = try #require(defaults.data(forKey: "agentpet.projectUsage"))
            let encoded = try #require(JSONSerialization.jsonObject(with: data) as? [String: [String: Any]])
            #expect(encoded.values.allSatisfy { Set($0.keys) == ["projectId", "projectName", "agent", "day", "tokens", "sessions"] })
        }
    }

    @Test func tokensAndSessionsAcrossAgentsSurviveReload() {
        withDefaults { defaults in
            let store = ProjectUsageStore(defaults: defaults)
            store.recordTokens(1_000, project: "/synthetic/one", agent: "claude")
            store.recordTokens(2_000, project: "/synthetic/two", agent: "codex")
            store.recordSession(project: "/synthetic/two", agent: "codex")
            let restored = ProjectUsageStore(defaults: defaults)
            #expect(restored.recordedRows() == store.recordedRows())
            #expect(restored.recordedRows().reduce(0) { $0 + $1.tokens } == 3_000)
            #expect(restored.recordedRows().reduce(0) { $0 + $1.sessions } == 1)
        }
    }
}
