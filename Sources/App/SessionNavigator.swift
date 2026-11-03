import AppKit
import AgentPetCore

/// A durable navigation snapshot: completed sessions may already have been pruned.
struct SessionNavigationTarget: Codable, Equatable, Sendable {
    var sessionID: String
    var agentKind: AgentKind
    var agentName: String?
    var project: String?
    var title: String?
    var terminalProgram: String?
    var terminalTTY: String?
    var terminalFocusURL: String?

    init(_ session: AgentSession) {
        sessionID = session.id
        agentKind = session.agentKind
        agentName = session.agentName
        project = session.project
        title = session.title
        terminalProgram = session.terminalProgram
        terminalTTY = session.terminalTTY
        terminalFocusURL = session.terminalFocusURL
    }

    var key: String { agentKind.rawValue + ":" + sessionID }

    var completedSession: AgentSession {
        AgentSession(id: sessionID, agentKind: agentKind, project: project,
                     title: title, state: .done, source: .hook, updatedAt: .distantPast,
                     terminalProgram: terminalProgram, terminalTTY: terminalTTY,
                     terminalFocusURL: terminalFocusURL, agentName: agentName)
    }
}

enum SessionNavigationResult: Equatable, Sendable {
    /// The OS accepted a supported conversation URL, or the exact terminal tab was found.
    case openedConversation
    /// This must NOT acknowledge a completion: an app activation is not a conversation jump.
    case applicationOnly
    case unavailable
    case failed

    var message: String? {
        switch self {
        case .openedConversation: return nil
        case .applicationOnly:
            return NSLocalizedString("The client is open, but this conversation could not be located. Reminder kept.", comment: "completion navigation")
        case .unavailable:
            return NSLocalizedString("This client has not provided a conversation location. Reminder kept.", comment: "completion navigation")
        case .failed:
            return NSLocalizedString("Could not open this conversation. Check that the client is installed and the session still exists. Reminder kept.", comment: "completion navigation")
        }
    }
}

@MainActor
enum SessionNavigator {
    enum Destination: Equatable {
        case conversationURL(URL, bundleID: String)
        case terminal(program: String, tty: String)
        case application(bundleID: String)
        case applicationNamed(String)
        case unavailable
    }

    private static let terminalBundleIDs: [String: String] = [
        "Apple_Terminal": "com.apple.Terminal", "iTerm.app": "com.googlecode.iterm2",
        "WarpTerminal": "dev.warp.Warp-Stable", "vscode": "com.microsoft.VSCode",
        "ghostty": "com.mitchellh.ghostty", "Hyper": "co.zeit.hyper", "Tabby": "org.tabby",
        "kitty": "net.kovidgoyal.kitty", "alacritty": "org.alacritty",
    ]

    static func destination(for target: SessionNavigationTarget) -> Destination {
        let program = target.terminalProgram
        if let program, ["Apple_Terminal", "iTerm.app"].contains(program),
           let tty = target.terminalTTY, tty.hasPrefix("/dev/tty"), tty.count > 8 {
            return .terminal(program: program, tty: tty)
        }
        if let raw = target.terminalFocusURL, let url = URL(string: raw),
           url.scheme?.lowercased() == "warp", url.host == "session", !url.path.isEmpty,
           program == nil || program == "WarpTerminal" {
            return .conversationURL(url, bundleID: "dev.warp.Warp-Stable")
        }
        // Respect the originating terminal/IDE. Do not redirect CLI work to a different app.
        if let program, let bundleID = terminalBundleIDs[program] {
            if program == "vscode", target.agentKind == .cursor { return .applicationNamed("Cursor") }
            return .application(bundleID: bundleID)
        }
        if target.agentKind == .codex,
           program == nil || program == "Codex" || program == "codex" {
            guard UUID(uuidString: target.sessionID) != nil else { return .unavailable }
            // Verified against the installed Codex desktop's OS URL route (2026-11-03).
            // No prompt/new-thread parameters: this only navigates to an existing conversation.
            var components = URLComponents()
            components.scheme = "codex"
            components.host = "threads"
            components.path = "/" + target.sessionID
            guard let url = components.url else { return .unavailable }
            return .conversationURL(url, bundleID: "com.openai.codex")
        }
        switch target.agentKind {
        case .cursor: return .applicationNamed("Cursor")
        case .windsurf: return .applicationNamed("Windsurf")
        case .antigravity: return .applicationNamed("Antigravity")
        default: return .unavailable
        }
    }

    static func open(_ target: SessionNavigationTarget) async -> SessionNavigationResult {
        let workspace = NSWorkspace.shared
        switch destination(for: target) {
        case .conversationURL(let url, let expectedBundleID):
            guard let app = workspace.urlForApplication(toOpen: url),
                  Bundle(url: app)?.bundleIdentifier == expectedBundleID else { return .failed }
            return workspace.open(url) ? .openedConversation : .failed
        case .terminal(let program, let tty):
            return await TerminalFocus.focusExact(program: program, tty: tty) ? .openedConversation : .failed
        case .application(let bundleID):
            guard let app = workspace.urlForApplication(withBundleIdentifier: bundleID) else { return .failed }
            return await activateOnly(app)
        case .applicationNamed(let name):
            let candidates = ["/Applications", NSHomeDirectory() + "/Applications"]
                .map { URL(fileURLWithPath: $0).appendingPathComponent(name + ".app") }
            guard let app = candidates.first(where: { Bundle(url: $0)?.executableURL != nil }) else { return .failed }
            return await activateOnly(app)
        case .unavailable: return .unavailable
        }
    }

    private static func activateOnly(_ url: URL) async -> SessionNavigationResult {
        do {
            _ = try await NSWorkspace.shared.openApplication(at: url, configuration: .init())
            return .applicationOnly
        } catch { return .failed }
    }
}
