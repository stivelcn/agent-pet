import Foundation
import AgentPetCore

/// Runtime-localized display text. Keep identifiers, paths and custom messages
/// out of localization; only built-in activity keys pass through the vocabulary.
enum InterfaceText {
    static func format(_ key: String, _ arguments: CVarArg..., bundle: Bundle = .main) -> String {
        String(format: bundle.localizedString(forKey: key, value: key, table: nil), arguments: arguments)
    }

    static func activity(_ message: String?, fallback: String, bundle: Bundle = .main) -> String {
        if let message, !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return ActivityFormatter.localizedMessage(message, bundle: bundle)
        }
        return bundle.localizedString(forKey: fallback, value: fallback, table: nil)
    }

    static func agentSummary(count: Int, kinds: Int, bundle: Bundle = .main) -> String {
        let agents = format(count == 1 ? "%d agent" : "%d agents", count, bundle: bundle)
        guard kinds > 1 else { return agents }
        return agents + " · " + format("%d kinds", kinds, bundle: bundle)
    }

    static func elapsed(seconds: Int, secondsLimit: Int = 60, bundle: Bundle = .main) -> String {
        let seconds = max(0, seconds)
        if seconds < secondsLimit { return format("%ds", seconds, bundle: bundle) }
        let minutes = seconds / 60
        if minutes < 60 { return format("%dm", minutes, bundle: bundle) }
        return format("%dh %dm", minutes / 60, minutes % 60, bundle: bundle)
    }
}
