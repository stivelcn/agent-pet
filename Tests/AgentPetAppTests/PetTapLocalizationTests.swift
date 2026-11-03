import Foundation
import Testing
@testable import agentpet

@MainActor
@Suite(.serialized)
struct PetTapLocalizationTests {
    private let englishTiers = [
        ["Hehe~", "That tickles!", "Hi there! 👋", "Oh! Hello~", "*purrs*", "Nyaa~"],
        ["I love you! 💕", "More pets please!", "Best human ever!", "So happy~ ✨"],
        ["MAXIMUM LOVE! 💖", "Can't stop smiling! 🥰", "I'm gonna melt~"],
    ]
    private let chineseTiers = [
        ["嘿嘿～", "好痒呀！", "你好呀！👋", "哎呀，你来啦～", "呼噜呼噜～", "喵呜～"],
        ["最喜欢你啦！💕", "再摸摸我嘛！", "你对我最好啦！", "好开心呀～✨"],
        ["喜欢你，满分！💖", "开心得合不拢嘴啦！🥰", "被你摸得心都化啦～"],
    ]

    private func localizationBundle(_ language: String) throws -> Bundle {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return try #require(Bundle(path: root.appendingPathComponent("Localizations/\(language).lproj").path))
    }

    @Test func allThirteenTapReactionsHaveChineseTranslations() throws {
        let zh = try localizationBundle("zh-Hans")
        let en = try localizationBundle("en")
        let keys = englishTiers.flatMap { $0 }
        let translations = chineseTiers.flatMap { $0 }
        #expect(keys.count == 13)
        for (key, translation) in zip(keys, translations) {
            #expect(zh.localizedString(forKey: key, value: nil, table: nil) == translation)
            #expect(en.localizedString(forKey: key, value: nil, table: nil) == key)
        }
    }

    @Test func tapsUseChineseAtEveryTierAndPreserveCooldown() async throws {
        let zh = try localizationBundle("zh-Hans")
        let model = PetWindowModel(key: "isolated-localization-test")
        // Exercise the actual click handler, including both continuous-tap thresholds.
        for tap in 1...6 {
            if tap > 1 { try await Task.sleep(for: .milliseconds(500)) }
            model.petTap(localizationBundle: zh)
            let tier = tap >= 6 ? 2 : tap >= 3 ? 1 : 0
            #expect(model.petTapCount == tap)
            #expect(chineseTiers[tier].contains(model.petReactionLine))
            #expect(model.isPetted)
            let line = model.petReactionLine
            model.petTap(localizationBundle: zh)
            #expect(model.petTapCount == tap)
            #expect(model.petReactionLine == line)
        }
    }

    @Test func nextTapResolvesItsCurrentLanguageRatherThanCachingEnglish() async throws {
        let zh = try localizationBundle("zh-Hans")
        let en = try localizationBundle("en")
        let model = PetWindowModel(key: "isolated-language-switch-test")
        model.petTap(localizationBundle: en)
        #expect(englishTiers[0].contains(model.petReactionLine))
        try await Task.sleep(for: .milliseconds(500))
        model.petTap(localizationBundle: zh)
        #expect(model.petTapCount == 2)
        #expect(chineseTiers[0].contains(model.petReactionLine))
    }
}
