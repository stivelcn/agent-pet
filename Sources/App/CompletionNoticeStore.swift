import Foundation
import AgentPetCore

struct CompletionNotice: Codable, Equatable, Identifiable, Sendable {
    var target: SessionNavigationTarget
    let completedAt: Date
    // A second turn in the same session has a different id. An old async click cannot dismiss it.
    var id: String { target.key + ":" + String(completedAt.timeIntervalSince1970) }
}

/// Unread completions are independent of the short-lived session list and token history.
/// No timer expires them. Acknowledgement, dismissal, or new work in that session clears them.
@MainActor
final class CompletionNoticeStore: ObservableObject {
    static let shared = CompletionNoticeStore(fileURL: URL(fileURLWithPath: AgentPetPaths.baseDir)
        .appendingPathComponent("completion-notices.json"))

    @Published private(set) var notices: [CompletionNotice] = []
    @Published private(set) var messages: [String: String] = [:]
    @Published private(set) var openingIDs: Set<String> = []
    @Published private(set) var persistenceError: String?
    private let fileURL: URL?
    private var completedThrough: [String: Date] = [:]
    private var latestActivity: [String: Date] = [:]

    private struct Saved: Codable {
        var notices: [CompletionNotice]
        var completedThrough: [String: Date]
    }

    /// nil keeps isolated tests entirely in memory.
    init(fileURL: URL? = nil) {
        self.fileURL = fileURL
        guard let fileURL, FileManager.default.fileExists(atPath: fileURL.path) else { return }
        do {
            let saved = try JSONDecoder().decode(Saved.self, from: Data(contentsOf: fileURL))
            notices = saved.notices.sorted { $0.completedAt > $1.completedAt }
            completedThrough = saved.completedThrough
        } catch { persistenceError = Self.storageError }
    }

    func record(_ session: AgentSession, at time: Date) {
        guard session.state == .done, session.source == .hook else { return }
        let target = SessionNavigationTarget(session)
        guard time > (completedThrough[target.key] ?? .distantPast),
              time >= (latestActivity[target.key] ?? .distantPast) else { return }
        let replaced = notices.filter { $0.target.key == target.key }
        for notice in replaced { messages.removeValue(forKey: notice.id) }
        completedThrough[target.key] = time
        notices.removeAll { $0.target.key == target.key }
        notices.append(CompletionNotice(target: target, completedAt: time))
        notices.sort { $0.completedAt > $1.completedAt }
        save()
    }

    func observeActivity(_ session: AgentSession, at time: Date) {
        guard session.state == .working || session.state == .waiting else { return }
        let key = SessionNavigationTarget(session).key
        latestActivity[key] = max(time, latestActivity[key] ?? .distantPast)
        let stale = notices.filter { $0.target.key == key && $0.completedAt < time }
        guard !stale.isEmpty else { return }
        for notice in stale { messages.removeValue(forKey: notice.id) }
        notices.removeAll { $0.target.key == key && $0.completedAt < time }
        completedThrough[key] = max(time, completedThrough[key] ?? .distantPast)
        save()
    }

    /// Titles/terminal information can arrive after Stop; update without changing identity or age.
    func refreshMetadata(from sessions: [AgentSession]) {
        var updated = notices
        for index in updated.indices {
            guard let session = sessions.first(where: {
                $0.id == updated[index].target.sessionID && $0.agentKind == updated[index].target.agentKind
            }) else { continue }
            let fresh = SessionNavigationTarget(session)
            if let value = fresh.title { updated[index].target.title = value }
            if let value = fresh.project { updated[index].target.project = value }
            if let value = fresh.terminalProgram { updated[index].target.terminalProgram = value }
            if let value = fresh.terminalTTY { updated[index].target.terminalTTY = value }
            if let value = fresh.terminalFocusURL { updated[index].target.terminalFocusURL = value }
        }
        guard updated != notices else { return }
        notices = updated
        save()
    }

    func dismiss(_ id: String) {
        guard notices.contains(where: { $0.id == id }) else { return }
        notices.removeAll { $0.id == id }
        messages.removeValue(forKey: id)
        save()
    }

    func dismissAll() {
        notices = []
        messages = [:]
        save()
    }

    func removeSession(_ sessionID: String) {
        for notice in notices.filter({ $0.target.sessionID == sessionID }) { dismiss(notice.id) }
    }

    func open(_ id: String,
              navigate: (SessionNavigationTarget) async -> SessionNavigationResult = { await SessionNavigator.open($0) }) async {
        guard let notice = notices.first(where: { $0.id == id }), !openingIDs.contains(id) else { return }
        openingIDs.insert(id)
        messages.removeValue(forKey: id)
        defer { openingIDs.remove(id) }
        let result = await navigate(notice.target)
        guard notices.contains(where: { $0.id == id }) else { return }
        if result == .openedConversation { dismiss(id) }
        else { messages[id] = result.message }
    }

    /// Include unread completions ONLY for planning pet windows, never as live work/usage.
    func planningSessions(live: [AgentSession]) -> [AgentSession] {
        let replacements = Dictionary(notices.map { ($0.target.key, $0.target.completedSession) }, uniquingKeysWith: { first, _ in first })
        let liveKeys = Set(live.map { SessionNavigationTarget($0).key })
        return live.map { session in
            if session.state == .idle || session.state == .registered,
               let pending = replacements[SessionNavigationTarget(session).key] { return pending }
            return session
        } + replacements.filter { !liveKeys.contains($0.key) }.map(\.value)
    }

    func notices(forWindow key: String, split: Bool, mappings: [ProjectPetMapping]) -> [CompletionNotice] {
        guard split else { return key == PetWindowPlanner.defaultKey ? notices : [] }
        return notices.filter { notice in
            let mapping = ProjectPetResolver.mapping(forProject: notice.target.project, mappings: mappings)
            let assignedKey = mapping.map { ProjectPetResolver.normalize($0.projectPath) } ?? PetWindowPlanner.defaultKey
            return assignedKey == key
        }
    }

    private static var storageError: String {
        NSLocalizedString("Completion reminders could not be saved or restored. They remain visible in this run.", comment: "completion persistence")
    }

    private func save() {
        guard let fileURL else { return }
        do {
            let data = try JSONEncoder().encode(Saved(notices: notices, completedThrough: completedThrough))
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: fileURL, options: .atomic)
            persistenceError = nil
        } catch { persistenceError = Self.storageError }
    }
}
