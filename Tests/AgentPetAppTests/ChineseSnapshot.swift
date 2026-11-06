import Foundation
import ObjectiveC
@testable import agentpet

/// SwiftPM test executables do not contain the app bundle's copied .lproj folders.
/// Render with the same Chinese strings that build-app.sh packages in the app.
private final class ChineseSnapshotBundle: Bundle, @unchecked Sendable {
    private static let chinese = Bundle(path: URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Localizations/zh-Hans.lproj").path)!

    override func localizedString(forKey key: String, value: String?, table tableName: String?) -> String {
        Self.chinese.localizedString(forKey: key, value: value, table: tableName)
    }
}

@MainActor
func withChineseSnapshot<T>(_ body: () throws -> T) rethrows -> T {
    _ = AppLanguage.shared
    let previous: AnyClass? = object_getClass(Bundle.main)
    object_setClass(Bundle.main, ChineseSnapshotBundle.self)
    defer { if let previous { object_setClass(Bundle.main, previous) } }
    return try body()
}
