import Foundation

/// Independent identities for this fork. No original preferences or files are imported.
public enum LocalConfiguration {
    public static let releaseIdentifier = "local.agentpet"
    public static let developmentIdentifier = "local.agentpet.dev"

    public static var isDevelopment: Bool {
        if let value = Bundle.main.object(forInfoDictionaryKey: "AgentPetDevelopmentBuild") as? Bool {
            return value
        }
        #if DEBUG
        return true
        #else
        return false
        #endif
    }

    public static var identifier: String {
        isDevelopment ? developmentIdentifier : releaseIdentifier
    }

    public static var displayName: String {
        isDevelopment ? "智能桌宠（开发版）" : "智能桌宠"
    }

    /// Local builds connect detected clients; tests and diagnostics can explicitly opt out.
    public static var hookConfigurationEnabled: Bool {
        allowsHookConfiguration(development: isDevelopment,
                                optIn: ProcessInfo.processInfo.environment["AGENTPET_ENABLE_DEV_HOOKS"])
    }

    public static func allowsHookConfiguration(development: Bool, optIn: String?) -> Bool {
        optIn != "0"
    }

    public static var preferencesSuite: String {
        let override = ProcessInfo.processInfo.environment["AGENTPET_PREFERENCES_SUITE"]
        return override.flatMap { $0.isEmpty ? nil : $0 } ?? (identifier + ".preferences")
    }
}

/// Explicit suites also isolate a bare SwiftPM executable from the upstream app.
public enum LocalPreferences {
    public static var defaults: UserDefaults {
        let suite = LocalConfiguration.preferencesSuite
        // Foundation rejects the app's own bundle identifier as an explicit suite.
        // The separate .preferences domain also retains the first development session.
        if suite == Bundle.main.bundleIdentifier { return .standard }
        return UserDefaults(suiteName: suite) ?? .standard
    }
}
