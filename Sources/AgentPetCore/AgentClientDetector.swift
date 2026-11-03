import Foundation

/// Looks for real applications/executables, never treating a leftover config folder as installation.
public enum AgentClientDetector {
    public static func detect(home: String = NSHomeDirectory(),
                              path: String = ProcessInfo.processInfo.environment["PATH"] ?? "",
                              applicationRoots: [String]? = nil,
                              systemBinaryDirectories: [String] = ["/opt/homebrew/bin", "/usr/local/bin"]) -> [AgentKind: String] {
        let fm = FileManager.default
        var bins = path.split(separator: ":").map(String.init).filter { $0.hasPrefix("/") }
        bins += systemBinaryDirectories + [home + "/.local/bin",
                 home + "/.bun/bin", home + "/.volta/bin", home + "/.npm-global/bin"]
        let nvm = home + "/.nvm/versions/node"
        for version in (try? fm.contentsOfDirectory(atPath: nvm)) ?? [] {
            bins.append(nvm + "/" + version + "/bin")
        }
        let commands: [(AgentKind, String)] = [
            (.claude, "claude"), (.codex, "codex"), (.gemini, "gemini"), (.cursor, "cursor"),
            (.opencode, "opencode"), (.windsurf, "windsurf"), (.antigravity, "antigravity"),
            (.copilot, "copilot"), (.kiroCLI, "kiro-cli"), (.droid, "droid"),
            (.pi, "pi"), (.grok, "grok"), (.jcode, "jcode")
        ]
        var found: [AgentKind: String] = [:]
        for (kind, name) in commands {
            if let binary = bins.map({ $0 + "/" + name }).first(where: fm.isExecutableFile(atPath:)) {
                found[kind] = binary
            }
        }
        let apps: [(AgentKind, String)] = [(.codex, "Codex"), (.cursor, "Cursor"),
                                          (.windsurf, "Windsurf"), (.antigravity, "Antigravity")]
        for root in applicationRoots ?? ["/Applications", home + "/Applications"] {
            for (kind, name) in apps where found[kind] == nil {
                let app = root + "/" + name + ".app"
                if let bundle = Bundle(path: app), let executable = bundle.executablePath,
                   fm.isExecutableFile(atPath: executable) { found[kind] = app }
            }
            // The desktop distribution can also bundle the CLI inside ChatGPT.app.
            let cli = root + "/ChatGPT.app/Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex"
            if found[.codex] == nil, fm.isExecutableFile(atPath: cli) { found[.codex] = cli }
        }
        return found
    }
}
