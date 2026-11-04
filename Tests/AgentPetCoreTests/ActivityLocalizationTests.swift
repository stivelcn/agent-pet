import Foundation
import Testing
@testable import AgentPetCore

@Suite(.serialized)
struct ActivityLocalizationTests {
    private func bundle(_ locale: String) throws -> Bundle {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return try #require(Bundle(path: root.appendingPathComponent("Localizations/\(locale).lproj").path))
    }

    @Test func allBuiltInActivityKeysHaveChineseAndEnglishTranslations() throws {
        let zh = try bundle("zh-Hans"), en = try bundle("en")
        #expect(ActivityFormatter.builtInMessageKeys.count >= 197)
        for key in ActivityFormatter.builtInMessageKeys {
            let chinese = zh.localizedString(forKey: key, value: "MISSING", table: nil)
            #expect(chinese != "MISSING", Comment(rawValue: key))
            #expect(chinese.range(of: "\\p{Han}", options: .regularExpression) != nil, Comment(rawValue: key))
            #expect(ActivityFormatter.localizedMessage(key, bundle: zh) == chinese)
            #expect(en.localizedString(forKey: key, value: "MISSING", table: nil) == key)
        }
    }

    @Test func everyPoolInEveryThemeUsesThePresentationLocalizer() throws {
        let zh = try bundle("zh-Hans")
        for theme in ActivityTheme.allCases {
            for pool in [theme.reading, theme.writing, theme.running, theme.searching,
                         theme.delegating, theme.thinking, theme.done, theme.waiting,
                         theme.skill, theme.generic] {
                for key in pool {
                    #expect(ActivityFormatter.builtInMessageKeys.contains(key))
                    #expect(ActivityFormatter.localizedMessage(key, bundle: zh) != key)
                }
            }
        }
    }

    @Test func screenshotSproutingStatusIsLocalizedAndWhitespaceIsHandled() throws {
        let zh = try bundle("zh-Hans")
        #expect(ActivityFormatter.localizedMessage("Sprouting…", bundle: zh) == "灵感发芽中…")
        #expect(ActivityFormatter.localizedMessage(" \nSprouting…\t", bundle: zh) == "灵感发芽中…")
    }

    @Test func languageSwitchDoesNotCacheAPreviousTranslation() throws {
        let zh = try bundle("zh-Hans"), en = try bundle("en")
        #expect(ActivityFormatter.localizedMessage("Compiling…", bundle: en) == "Compiling…")
        #expect(ActivityFormatter.localizedMessage("Compiling…", bundle: zh) == "编译中…")
        #expect(ActivityFormatter.localizedMessage("Compiling…", bundle: en) == "Compiling…")
    }

    @Test func clientContentPathsAndOtherUIKeysAreNotTranslated() throws {
        let zh = try bundle("zh-Hans")
        for text in ["Fix login bug", "Settings", "Codex", "agent_pet", "GPT-5 Codex",
                     "/Users/me/Project/Settings.swift", "  Please review my patch.\n", "自定义任务"] {
            #expect(ActivityFormatter.localizedMessage(text, bundle: zh) == text)
        }
    }

    @Test func fileHintsStillEmitStableKeysAndTranslateAtDisplayTime() throws {
        let zh = try bundle("zh-Hans")
        let cases = [
            ("Read", "Tests/DemoTests.swift", "Reviewing tests…", "审阅测试中…"),
            ("Edit", "Tests/DemoTests.swift", "Refining tests…", "完善测试中…"),
            ("Read", "README.md", "Reading the docs…", "阅读文档中…"),
            ("Write", "README.md", "Updating the docs…", "更新文档中…"),
            ("Read", "settings.json", "Parsing config…", "解析配置中…"),
            ("Edit", "settings.toml", "Adjusting config…", "调整配置中…"),
        ]
        for (tool, path, key, expected) in cases {
            let message = try #require(ActivityFormatter.activityMessage(
                eventName: "PreToolUse", sessionId: "isolated-translation-test", toolName: tool,
                toolInput: ToolActivityInput(filePath: path), explicitMessage: nil))
            #expect(message == key)
            #expect(ActivityFormatter.localizedMessage(message, bundle: zh) == expected)
        }
    }

    @Test func tickerTranslatesBuiltInStatusButPreservesProjectAndClient() throws {
        let session = AgentSession(id: "isolated-test", agentKind: .codex, project: "/tmp/agent_pet",
                                   state: .working, message: "Sprouting…", source: .hook, updatedAt: Date())
        #expect(TickerFormatter.line(for: session, bundle: try bundle("zh-Hans")) == "Codex [agent_pet] → 灵感发芽中…")
        #expect(TickerFormatter.line(for: session, bundle: try bundle("en")) == "Codex [agent_pet] → Sprouting…")
    }

    @Test func tickerTranslatesFallbackStatesAndGenericAgentLabel() throws {
        let zh = try bundle("zh-Hans")
        for message in [nil, "", " \n\t"] as [String?] {
            let session = AgentSession(id: "isolated-test", agentKind: .cli, project: "/tmp/agent_pet",
                                       state: .working, message: message, source: .hook, updatedAt: Date())
            #expect(TickerFormatter.line(for: session, bundle: zh) == "编程助手 [agent_pet] → 工作中")
        }
        #expect(TickerFormatter.agentLabel(for: .unknown, bundle: zh) == "编程助手")
    }

    @Test func tickerDoesNotTranslateArbitraryMessagesOrProjectAliases() throws {
        let session = AgentSession(id: "isolated-test", agentKind: .codex, project: "/tmp/agent_pet",
                                   state: .working, message: "Fix login bug", source: .hook, updatedAt: Date())
        #expect(TickerFormatter.line(for: session, projectNames: [ProjectNames.id(for: "/tmp/agent_pet"): "My Project"],
                                     bundle: try bundle("zh-Hans")) == "Codex [My Project] → Fix login bug")
    }
}
