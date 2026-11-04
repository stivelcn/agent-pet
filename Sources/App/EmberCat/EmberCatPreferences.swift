import Foundation

/// Only the requested features cross the boundary. Never import pet/Dock/Sparkle keys.
enum EmberCatPreferenceMigration {
    static let sourceDomain = "com.johann.embercat"
    static let markerKey = "agentpet.embercat.imported.v1"
    static let importedCountKey = "agentpet.embercat.importedKeyCount"
    static let featureKeys = ["notchFlamesEnabled", "notchFlamePalette", "notchFlameAppearance", "showsTokenRate"]

    @discardableResult
    static func importOnce(source: [String: Any]?, into destination: UserDefaults) -> Int {
        guard !destination.bool(forKey: markerKey), let source else { return 0 }
        var count = 0
        for key in featureKeys where destination.object(forKey: key) == nil {
            guard let value = source[key] else { continue }
            // Preserve the original JSON bytes, including the user's exact color thresholds.
            if key == "notchFlamePalette" || key == "notchFlameAppearance" {
                guard value is Data else { continue }
            } else {
                guard value is Bool else { continue }
            }
            destination.set(value, forKey: key)
            count += 1
        }
        destination.set(count, forKey: importedCountKey)
        destination.set(true, forKey: markerKey)
        return count
    }

    static func allowsLegacyImport(environment: [String: String]) -> Bool {
        environment["AGENTPET_EMBERCAT_ENABLED"] != "0"
            && environment["AGENTPET_PREFERENCES_SUITE"] == nil
            && environment["AGENTPET_DATA_DIR"] == nil
    }
}

enum EmberCatRateFormat {
    static func text(speed: Double, precision: Int = 1) -> String {
        let value = speed.isFinite ? max(0, speed) : 0
        return String(format: "%.*f token/s", locale: Locale(identifier: "en_US_POSIX"),
                      min(2, max(0, precision)), value)
    }
}
