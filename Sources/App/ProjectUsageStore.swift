import Foundation
import AgentPetCore

/// Local per-project, per-agent daily usage. No records are uploaded.
@MainActor
final class ProjectUsageStore: ObservableObject {
    static let shared = ProjectUsageStore()

    struct Row: Codable, Equatable {
        var projectId: String
        var projectName: String
        var agent: String
        var day: String
        var tokens: Int
        var sessions: Int
        var costUSD: Double = 0

        init(projectId: String, projectName: String, agent: String, day: String, tokens: Int, sessions: Int, costUSD: Double = 0) {
            self.projectId = projectId
            self.projectName = projectName
            self.agent = agent
            self.day = day
            self.tokens = tokens
            self.sessions = sessions
            self.costUSD = costUSD
        }

        private enum CodingKeys: String, CodingKey {
            case projectId, projectName, agent, day, tokens, sessions, costUSD
        }

        /// Custom decode so rows persisted before costUSD existed still load, defaulting to 0.
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            projectId = try c.decode(String.self, forKey: .projectId)
            projectName = try c.decode(String.self, forKey: .projectName)
            agent = try c.decode(String.self, forKey: .agent)
            day = try c.decode(String.self, forKey: .day)
            tokens = try c.decode(Int.self, forKey: .tokens)
            sessions = try c.decode(Int.self, forKey: .sessions)
            costUSD = try c.decodeIfPresent(Double.self, forKey: .costUSD) ?? 0
        }
    }

    private static let storageKey = "agentpet.projectUsage"
    /// Keyed by "projectId|agent|day".
    @Published private var rows: [String: Row]
    private let defaults: UserDefaults
    private let now: () -> Date
    private let calendar: Calendar

    static let unassignedProjectID = "__unassigned__"

    @Published private(set) var todayCostUSD: Double = 0
    @Published private(set) var monthlyCostUSD: Double = 0

    init(defaults: UserDefaults = LocalPreferences.defaults,
         now: @escaping () -> Date = Date.init, calendar: Calendar = .current) {
        self.defaults = defaults
        self.now = now
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.timeZone = calendar.timeZone
        self.calendar = gregorian
        rows = (defaults.data(forKey: Self.storageKey)
            .flatMap { try? JSONDecoder().decode([String: Row].self, from: $0) }) ?? [:]
        // Daily aggregates are the historical ledger. Never age them out; the
        // former 120-day cleanup made older monthly reports irrecoverable.
        recomputeCostTotals()
    }

    // MARK: - Recording

    func recordTokens(_ tokens: Int, project: String?, agent: String, costUSD: Double = 0) {
        record(project: project, agent: agent, tokens: tokens, sessions: 0, costUSD: costUSD)
    }
    func recordSession(project: String?, agent: String) {
        record(project: project, agent: agent, tokens: 0, sessions: 1)
    }

    private func record(project: String?, agent: String, tokens: Int, sessions: Int, costUSD: Double = 0) {
        let agent = agent.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !agent.isEmpty, tokens >= 0, sessions >= 0, tokens > 0 || sessions > 0 else { return }
        // Missing project metadata must not discard otherwise genuine usage.
        let (pid, pname): (String, String)
        if let project, !project.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            (pid, pname) = Self.projectIdentity(project)
        } else {
            (pid, pname) = (Self.unassignedProjectID, "Unknown project")
        }
        let day = today()
        let key = "\(pid)|\(agent)|\(day)"
        var r = rows[key] ?? Row(projectId: pid, projectName: pname, agent: agent, day: day, tokens: 0, sessions: 0)
        r.tokens += tokens
        r.sessions += sessions
        r.costUSD += costUSD.isFinite ? max(0, costUSD) : 0
        r.projectName = pname
        rows[key] = r
        persist()
        recomputeCostTotals()
    }

    // MARK: - Local summaries

    /// Projects seen so far as (id, folder name), most recently used first. Only
    /// those used in the last `withinDays` days, plus any id in `alwaysInclude`
    /// (projects that already have a name), so the Settings list stays short.
    func knownProjects(withinDays: Int = 7, alwaysInclude: Set<String> = []) -> [(id: String, folder: String)] {
        let cutoff = dayString(daysAgo: withinDays)
        var latest: [String: (day: String, folder: String)] = [:]
        for r in rows.values where latest[r.projectId].map({ r.day > $0.day }) ?? true {
            latest[r.projectId] = (r.day, r.projectName)
        }
        return latest
            .filter { $0.key != Self.unassignedProjectID && ($0.value.day >= cutoff || alwaysInclude.contains($0.key)) }
            .sorted { $0.value.day != $1.value.day ? $0.value.day > $1.value.day : $0.value.folder < $1.value.folder }
            .map { (id: $0.key, folder: $0.value.folder) }
    }

    /// Tokens and sessions per agent for today and this calendar month.
    func byAgent() -> [AgentUsageTotal] {
        AgentUsage.totals(
            rows.values.map { AgentUsage.Record(agent: $0.agent, day: $0.day, tokens: $0.tokens, sessions: $0.sessions) },
            today: today())
    }

    /// A snapshot for local reports and tests; there is no upload queue.
    func recordedRows() -> [Row] { rows.sorted { $0.key < $1.key }.map(\.value) }

    // MARK: - Helpers

    static func projectIdentity(_ path: String) -> (id: String, name: String) {
        // One hash for the usage rows and the custom names (ProjectNames), so a
        // name can never stop matching its project.
        (ProjectNames.id(for: path), String(ProjectNames.folderName(path).prefix(60)))
    }
    private func today() -> String {
        PetCare.dayKey(for: now(), calendar: calendar)
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(rows) {
            defaults.set(data, forKey: Self.storageKey)
        }
    }

    private func recomputeCostTotals() {
        let day = today()
        let month = String(day.prefix(7))
        todayCostUSD = rows.values.filter { $0.day == day }.reduce(0) { $0 + $1.costUSD }
        monthlyCostUSD = rows.values.filter { $0.day.hasPrefix(month) }.reduce(0) { $0 + $1.costUSD }
    }
    private func dayString(daysAgo: Int) -> String {
        let date = calendar.date(byAdding: .day, value: -daysAgo, to: now()) ?? now()
        return PetCare.dayKey(for: date, calendar: calendar)
    }
}
