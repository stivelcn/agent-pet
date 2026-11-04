import Foundation
import Testing
import AgentPetCore
@testable import agentpet

@MainActor
@Suite(.serialized)
struct InterfaceLocalizationTests {
    private func bundle(_ locale: String = "zh-Hans") throws -> Bundle {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return try #require(Bundle(path: root.appendingPathComponent("Localizations/\(locale).lproj").path))
    }

    @Test func liveRowsAndNotificationBodiesUseTheSameActivityTranslation() throws {
        let zh = try bundle()
        #expect(InterfaceText.activity("Sprouting…", fallback: "Working", bundle: zh) == "灵感发芽中…")
        #expect(InterfaceText.activity("Awaiting input…", fallback: "Waiting for you", bundle: zh) == "等待输入中…")
        #expect(InterfaceText.activity(nil, fallback: "Working", bundle: zh) == "工作中")
        #expect(InterfaceText.activity("\n\t", fallback: "Waiting for you", bundle: zh) == "等你来啦")
        #expect(InterfaceText.activity("Fix login bug", fallback: "Working", bundle: zh) == "Fix login bug")
    }

    @Test func agentSummariesHandleZeroOneAndSeveralKinds() throws {
        let zh = try bundle(), en = try bundle("en")
        #expect(InterfaceText.agentSummary(count: 0, kinds: 0, bundle: zh) == "0 个编程助手")
        #expect(InterfaceText.agentSummary(count: 1, kinds: 1, bundle: zh) == "1 个编程助手")
        #expect(InterfaceText.agentSummary(count: 3, kinds: 2, bundle: zh) == "3 个编程助手 · 2 类")
        #expect(InterfaceText.agentSummary(count: 1, kinds: 1, bundle: en) == "1 agent")
        #expect(InterfaceText.agentSummary(count: 3, kinds: 2, bundle: en) == "3 agents · 2 kinds")
    }

    @Test func elapsedLabelsAreLocalizedAtMinuteAndHourBoundaries() throws {
        let zh = try bundle(), en = try bundle("en")
        for (seconds, expected) in [(-3, "0 秒"), (0, "0 秒"), (59, "59 秒"), (60, "1 分钟"),
                                    (3599, "59 分钟"), (3600, "1 小时 0 分钟"), (3900, "1 小时 5 分钟")] {
            #expect(InterfaceText.elapsed(seconds: seconds, bundle: zh) == expected)
        }
        #expect(InterfaceText.elapsed(seconds: 180, bundle: en) == "3m")
        #expect(InterfaceText.elapsed(seconds: 3900, bundle: en) == "1h 5m")
    }

    @Test func notificationTitlesPreserveTheActualProjectName() throws {
        let zh = try bundle()
        #expect(InterfaceText.format("%@ needs input", "agent_pet", bundle: zh) == "agent_pet 需要你的输入")
        #expect(InterfaceText.format("%@ finished", "My App", bundle: zh) == "My App 已完成")
        #expect(zh.localizedString(forKey: "Agent completed its turn", value: nil, table: nil) == "编程助手已完成本轮任务")
    }

    @Test func breakSettingsAndMessagesFormatNumbersInChinese() throws {
        let zh = try bundle()
        #expect(InterfaceText.format("Work for: %d min", 45, bundle: zh) == "工作时长：45 分钟")
        #expect(InterfaceText.format("Break length: %d min", 5, bundle: zh) == "休息时长：5 分钟")
        #expect(InterfaceText.format("You've worked %d min — rest %d min 😴", 45, 5, bundle: zh) == "你已工作 45 分钟，休息 5 分钟吧 😴")
        #expect(InterfaceText.format("Worked %d min — let's rest %d min 😴", 45, 5, bundle: zh) == "忙了 45 分钟，一起休息 5 分钟吧 😴")
        #expect(zh.localizedString(forKey: "Break's over — back to it! 💪", value: nil, table: nil) == "休息结束，继续加油吧！💪")
    }

    @Test func careLabelsAndAchievementCountsAreLocalized() throws {
        let zh = try bundle()
        #expect(InterfaceText.format("Lv %d", 3, bundle: zh) == "等级 3")
        #expect(InterfaceText.format("%@ XP", "1,500", bundle: zh) == "1,500 经验")
        #expect(InterfaceText.format("%@ / %@ XP", "10", "100", bundle: zh) == "10 / 100 经验")
        #expect(InterfaceText.format("%d of %d unlocked", 2, 15, bundle: zh) == "已解锁 2 / 15 项")
    }

    @Test func historyOnboardingAndSoundPickerLabelsHaveChineseTranslations() throws {
        let zh = try bundle()
        for (key, expected) in [
            ("Today", "今天"), ("Past 7 Days", "最近 7 天"), ("Past 30 Days", "最近 30 天"),
            ("Pick your pet", "选择你的宠物"), ("Connect an agent", "连接编程助手"),
            ("Choose", "选择"), ("Choose a sound file", "选择声音文件"),
            ("Time for a break", "该休息一下啦"), (" (blank = live activity)", "（留空则显示实时状态）"),
        ] {
            #expect(zh.localizedString(forKey: key, value: nil, table: nil) == expected)
        }
        for filter in HistoryTabView.Filter.allCases {
            #expect(zh.localizedString(forKey: filter.rawValue, value: nil, table: nil) != filter.rawValue)
        }
    }

    @Test func previewTranslatesTheActionButNotTheFilename() throws {
        let zh = try bundle()
        #expect(InterfaceText.format("Editing %@", "SettingsModel.swift", bundle: zh) == "正在编辑 SettingsModel.swift")
        #expect(zh.localizedString(forKey: "Fix login bug", value: nil, table: nil) == "修复登录问题")
    }

    @Test func customBubbleTextIsPreservedEvenWhenItMatchesABuiltInKey() {
        let settings = BubbleMessages()
        let oldSource = settings.source, oldCustom = settings.custom
        defer { settings.source = oldSource; settings.custom = oldCustom }
        settings.source = .custom
        settings.custom = [BubbleMessages.allKey: [PetMood.working.rawValue: ["Sprouting…"]]]
        #expect(settings.line(for: .codex, mood: .working, seed: "isolated-test") == "Sprouting…")
        settings.setText("My custom message", for: AgentKind.codex.rawValue, mood: .working)
        #expect(settings.line(for: .codex, mood: .working, seed: "isolated-test") == "My custom message")
    }
}
