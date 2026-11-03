import Testing
import Foundation
@testable import AgentPetCore

@Suite(.serialized)
final class ActivityFormatterTests {

    // MARK: - Rotation

    @Test func test_rotation_doesNotRepeatConsecutively() {
        let first = ActivityFormatter.activityMessage(
            eventName: "PreToolUse", sessionId: "rot1",
            toolName: "Read", toolInput: nil, explicitMessage: nil
        )
        let second = ActivityFormatter.activityMessage(
            eventName: "PreToolUse", sessionId: "rot1",
            toolName: "Read", toolInput: nil, explicitMessage: nil
        )
        #expect((first) != (second), Comment(rawValue: "consecutive calls same tool should rotate"))
    }

    @Test func test_rotation_cyclesFullPool() {
        // reading pool has 5 phrases — 5 distinct calls must yield 5 distinct phrases
        let poolSize = 5
        var seen = Set<String?>()
        for _ in 0..<poolSize {
            let msg = ActivityFormatter.activityMessage(
                eventName: "PreToolUse", sessionId: "rot2",
                toolName: "Read", toolInput: nil, explicitMessage: nil
            )
            seen.insert(msg)
        }
        #expect((seen.count) == (poolSize), Comment(rawValue: "should cycle through all \(poolSize) reading phrases"))
    }

    // MARK: - Tool categorization

    @Test func test_toolCategory_matchesClaudeToolNames() {
        let cases: [(String, [String])] = [
            ("Read", ActivityTheme.chef.reading),
            ("Edit", ActivityTheme.chef.writing),
            ("Write", ActivityTheme.chef.writing),
            ("MultiEdit", ActivityTheme.chef.writing),
            ("Bash", ActivityTheme.chef.running),
            ("Glob", ActivityTheme.chef.searching),
            ("Grep", ActivityTheme.chef.searching),
            ("WebSearch", ActivityTheme.chef.searching),
            ("WebFetch", ActivityTheme.chef.searching),
            ("Agent", ActivityTheme.chef.delegating),
            ("Task", ActivityTheme.chef.delegating),
            ("Skill", ActivityTheme.chef.skill),
        ]
        for (toolName, pool) in cases {
            let msg = ActivityFormatter.activityMessage(
                eventName: "PreToolUse", sessionId: "cat-claude-\(toolName)",
                toolName: toolName, toolInput: nil, explicitMessage: nil
            )
            #expect(pool.contains(msg ?? ""), Comment(rawValue: "\(toolName) -> \(msg ?? "nil") not in expected pool"))
        }
    }

    @Test func test_toolCategory_matchesCursorToolNames() {
        let cases: [(String, [String])] = [
            ("read_file", ActivityTheme.chef.reading),
            ("edit_file", ActivityTheme.chef.writing),
            ("delete_file", ActivityTheme.chef.writing),
            ("run_terminal_cmd", ActivityTheme.chef.running),
            ("codebase_search", ActivityTheme.chef.searching),
            ("grep_search", ActivityTheme.chef.searching),
            ("list_dir", ActivityTheme.chef.searching),
        ]
        for (toolName, pool) in cases {
            let msg = ActivityFormatter.activityMessage(
                eventName: "preToolUse", sessionId: "cat-cursor-\(toolName)",
                toolName: toolName, toolInput: nil, explicitMessage: nil
            )
            #expect(pool.contains(msg ?? ""), Comment(rawValue: "\(toolName) -> \(msg ?? "nil") not in expected pool"))
        }
    }

    // MARK: - Extension hints

    @Test func test_extensionHint_testFile_reading() {
        let input = ToolActivityInput(filePath: "Tests/FooTests/BarTests.swift")
        let msg = ActivityFormatter.activityMessage(
            eventName: "PreToolUse", sessionId: "ext1",
            toolName: "Read", toolInput: input, explicitMessage: nil
        )
        #expect((msg) == ("Reviewing tests…"))
    }

    @Test func test_extensionHint_testFile_writing() {
        let input = ToolActivityInput(filePath: "Tests/FooTests/BarTests.swift")
        let msg = ActivityFormatter.activityMessage(
            eventName: "PreToolUse", sessionId: "ext2",
            toolName: "Edit", toolInput: input, explicitMessage: nil
        )
        #expect((msg) == ("Refining tests…"))
    }

    @Test func test_extensionHint_markdown_reading() {
        let input = ToolActivityInput(filePath: "README.md")
        let msg = ActivityFormatter.activityMessage(
            eventName: "PreToolUse", sessionId: "ext3",
            toolName: "Read", toolInput: input, explicitMessage: nil
        )
        #expect((msg) == ("Reading the docs…"))
    }

    @Test func test_extensionHint_markdown_writing() {
        let input = ToolActivityInput(filePath: "docs/guide.md")
        let msg = ActivityFormatter.activityMessage(
            eventName: "PreToolUse", sessionId: "ext4",
            toolName: "Write", toolInput: input, explicitMessage: nil
        )
        #expect((msg) == ("Updating the docs…"))
    }

    @Test func test_extensionHint_json_reading() {
        let input = ToolActivityInput(filePath: "config/settings.json")
        let msg = ActivityFormatter.activityMessage(
            eventName: "PreToolUse", sessionId: "ext5",
            toolName: "Read", toolInput: input, explicitMessage: nil
        )
        #expect((msg) == ("Parsing config…"))
    }

    @Test func test_extensionHint_plist_writing() {
        let input = ToolActivityInput(filePath: "Info.plist")
        let msg = ActivityFormatter.activityMessage(
            eventName: "PreToolUse", sessionId: "ext6",
            toolName: "Edit", toolInput: input, explicitMessage: nil
        )
        #expect((msg) == ("Adjusting config…"))
    }

    // MARK: - State messages

    @Test func test_stateMessage_done_returnsPhrase() {
        #expect((ActivityFormatter.stateMessage(for: .done)) != nil)
    }

    @Test func test_stateMessage_waiting_returnsPhrase() {
        #expect((ActivityFormatter.stateMessage(for: .waiting)) != nil)
    }

    @Test func test_stateMessage_idle_returnsNil() {
        #expect((ActivityFormatter.stateMessage(for: .idle)) == nil)
    }

    @Test func test_stateMessage_working_returnsNil() {
        #expect((ActivityFormatter.stateMessage(for: .working)) == nil)
    }

    @Test func test_stateMessage_done_rotates() {
        let first  = ActivityFormatter.stateMessage(for: .done)
        let second = ActivityFormatter.stateMessage(for: .done)
        #expect((first) != (second), Comment(rawValue: "done phrases should rotate"))
    }
}
