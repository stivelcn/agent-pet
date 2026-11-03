import Foundation

/// Shared JSON coders so the CLI helper and the daemon agree on the wire
/// format (notably the date strategy).
public enum EventCoding {
    public static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .secondsSince1970
        return e
    }()

    public static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .secondsSince1970
        return d
    }()
}

/// Default on-disk locations used by both the daemon and the CLI helper.
public enum AgentPetPaths {
    public static func baseDirectory(home: String, development: Bool, override: String? = nil) -> String {
        if let override, override.hasPrefix("/"), !override.isEmpty {
            return URL(fileURLWithPath: override, isDirectory: true).standardizedFileURL.path
        }
        return home + (development ? "/.agentpet-local-dev" : "/.agentpet-local")
    }

    public static var baseDir: String {
        baseDirectory(home: NSHomeDirectory(), development: LocalConfiguration.isDevelopment,
                      override: ProcessInfo.processInfo.environment["AGENTPET_DATA_DIR"])
    }
    public static var socketPath: String { baseDir + "/agentpet.sock" }
    public static var queueDir: String { baseDir + "/queue" }
}
