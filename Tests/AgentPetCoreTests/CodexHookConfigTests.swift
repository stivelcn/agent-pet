import Testing
import Foundation
@testable import AgentPetCore

@Suite(.serialized)
final class CodexHookConfigTests {
    @Test func testEmptyConfigAddsFeaturesTable() {
        let out = CodexHookConfig.enableHooks(in: "")
        #expect((out) == ("\n[features]\nhooks = true\n"))
        #expect(CodexHookConfig.alreadyEnabled(out!))
    }

    @Test func testAlreadyEnabledHooksIsNoOp() {
        #expect((CodexHookConfig.enableHooks(in: "[features]\nhooks = true\n")) == nil)
    }

    @Test func testCodexHooksAliasAloneStillAddsModernKey() {
        // `codex_hooks` is a deprecated alias recent Codex (Desktop 5.x) ignores,
        // so a config with only that must still get a real `hooks = true`.
        let out = CodexHookConfig.enableHooks(in: "[features]\ncodex_hooks = true\n")
        #expect((out) != nil)
        #expect(out!.contains("hooks = true"))
        #expect(CodexHookConfig.alreadyEnabled(out!))
    }

    @Test func testFlipsHooksFalseToTrue() {
        let out = CodexHookConfig.enableHooks(in: "[features]\nhooks = false\n")
        #expect((out) == ("[features]\nhooks = true\n"))
    }

    @Test func testFlipsCodexHooksFalseToTrueWithoutDuplicate() {
        let out = CodexHookConfig.enableHooks(in: "[features]\ncodex_hooks = false\n")!
        #expect((out.components(separatedBy: "true").count - 1) == (1), Comment(rawValue: "exactly one truthy flag, no duplicate"))
        #expect(CodexHookConfig.alreadyEnabled(out))
    }

    @Test func testInsertsUnderExistingFeaturesPreservingOtherKeys() {
        let out = CodexHookConfig.enableHooks(in: "model = \"o3\"\n\n[features]\nweb_search = true\n")!
        #expect(out.contains("hooks = true"))
        #expect(out.contains("web_search = true"), Comment(rawValue: "existing key kept"))
        #expect(out.contains("model = \"o3\""), Comment(rawValue: "unrelated key kept"))
        #expect(CodexHookConfig.alreadyEnabled(out))
    }

    @Test func testAppendsFeaturesWhenAbsentPreservingContent() {
        let out = CodexHookConfig.enableHooks(in: "model = \"o3\"")!
        #expect(out.contains("model = \"o3\""))
        #expect(out.contains("[features]"))
        #expect(out.contains("hooks = true"))
    }

    @Test func testCommentedFlagIsNotTreatedAsEnabled() {
        #expect(!(CodexHookConfig.alreadyEnabled("# hooks = true\n")))
    }
}
