import Testing
import Foundation

/// `Localizations/en.lproj/Localizable.strings` is the base/source-of-truth
/// file translators work from (its own header says so: "Keys are the
/// English UI text."). When a key ships translated in vi/zh-Hans/zh-Hant
/// but never gets added to the base file, anyone adding a new locale from
/// en.lproj — as this project's README already hints at with a fourth
/// README translation — will miss that string entirely, since there is
/// nothing in the base file telling them it needs translating.
///
/// That's exactly what happened to the achievements / per-project-pets /
/// break-reminder strings from PR #27 and #28: all three shipped locales
/// have them, en.lproj didn't. This test only checks that direction (every
/// locale's keys must exist in the base file) — a key that is *only* in
/// en.lproj is fine, since new strings routinely land untranslated and get
/// a locale follow-up later (see `f817127` + `1469780`, or issue #43).
@Suite(.serialized)
final class LocalizationParityTests {
    private static let localizationsDir: URL = {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // LocalizationParityTests.swift
            .deletingLastPathComponent() // AgentPetCoreTests
            .deletingLastPathComponent() // Tests
            .appendingPathComponent("Localizations")
    }()

    private static let translatedLocales = ["vi", "zh-Hans", "zh-Hant"]

    private func keys(forLocale locale: String) throws -> Set<String> {
        let path = Self.localizationsDir
            .appendingPathComponent("\(locale).lproj")
            .appendingPathComponent("Localizable.strings")
        let dict = try #require(NSDictionary(contentsOf: path) as? [String: String], Comment(rawValue: "Could not parse \(path.path) as a strings file"))
        return Set(dict.keys)
    }

    @Test func testBaseFileHasEveryKeyEachTranslationDeclares() throws {
        let base = try keys(forLocale: "en")
        #expect(!(base.isEmpty), Comment(rawValue: "en.lproj should not be empty"))

        for locale in Self.translatedLocales {
            let localeKeys = try keys(forLocale: locale)
            let missingFromBase = localeKeys.subtracting(base)
            #expect(missingFromBase.isEmpty, Comment(rawValue: "en.lproj is missing keys that \(locale).lproj already translates: \(missingFromBase.sorted())"))
        }
    }
}
