import Testing
import Foundation
@testable import AgentPetCore

@Suite(.serialized)
final class TranscriptUsageTests {

    private var path: String!

    private func setUp() {

        path = NSTemporaryDirectory() + "agentpet-usage-\(UUID().uuidString).jsonl"
        TranscriptReader.clearCache()
    }

    private func tearDown() {
        try? FileManager.default.removeItem(atPath: path)

    }

    private func append(_ lines: [String]) {
        let data = (lines.joined(separator: "\n") + "\n").data(using: .utf8)!
        if let handle = FileHandle(forWritingAtPath: path) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            handle.write(data)
        } else {
            try? data.write(to: URL(fileURLWithPath: path))
        }
    }

    private func assistantLine(input: Int, output: Int) -> String {
        #"{"type":"assistant","message":{"usage":{"input_tokens":\#(input),"output_tokens":\#(output)},"content":[{"type":"text","text":"hi"}]}}"#
    }

    @Test func testSumsUsageAcrossLines() {
        setUp()
        defer { tearDown() }
        append([
            #"{"type":"user","message":{"content":"do the thing"}}"#,
            assistantLine(input: 1_000, output: 250),
            assistantLine(input: 2_000, output: 750),
        ])
        #expect((TranscriptReader.newUsageTokens(at: path)) == (4_000))
    }

    @Test func testSecondCallReturnsOnlyTheDelta() {
        setUp()
        defer { tearDown() }
        append([assistantLine(input: 500, output: 100)])
        #expect((TranscriptReader.newUsageTokens(at: path)) == (600))
        #expect((TranscriptReader.newUsageTokens(at: path)) == (0), Comment(rawValue: "nothing new yet"))
        append([assistantLine(input: 300, output: 50)])
        #expect((TranscriptReader.newUsageTokens(at: path)) == (350))
    }

    @Test func testIgnoresLinesWithoutUsage() {
        setUp()
        defer { tearDown() }
        append([
            #"{"type":"user","message":{"content":"hello"}}"#,
            #"{"type":"summary","summary":"A chat"}"#,
        ])
        #expect((TranscriptReader.newUsageTokens(at: path)) == (0))
    }

    @Test func testPartialTrailingLineIsLeftForNextCall() {
        setUp()
        defer { tearDown() }
        append([assistantLine(input: 100, output: 100)])
        // A torn line with no trailing newline must not be consumed.
        let torn = #"{"type":"assistant","message":{"usage":{"input_tokens":9999"#
        if let handle = FileHandle(forWritingAtPath: path) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            handle.write(torn.data(using: .utf8)!)
        }
        #expect((TranscriptReader.newUsageTokens(at: path)) == (200))
        // Complete the torn line: now it should be picked up.
        if let handle = FileHandle(forWritingAtPath: path) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            handle.write(#","output_tokens":1}}}"#.data(using: .utf8)!)
            handle.write("\n".data(using: .utf8)!)
        }
        #expect((TranscriptReader.newUsageTokens(at: path)) == (10_000))
    }

    @Test func testUnreadableFileReturnsNil() {
        setUp()
        defer { tearDown() }
        #expect((TranscriptReader.newUsageTokens(at: "/nonexistent/nope.jsonl")) == nil)
    }

    // MARK: - Each reply counts once

    private func reply(id: String, at stamp: String? = nil, input: Int, output: Int, block: String = "text") -> String {
        let time = stamp.map { #","timestamp":"\#($0)""# } ?? ""
        return #"{"type":"assistant"\#(time),"message":{"id":"\#(id)","usage":{"input_tokens":\#(input),"output_tokens":\#(output)},"content":[{"type":"\#(block)"}]}}"#
    }

    /// Claude Code writes one line per content block of a reply (thinking,
    /// text, tool_use), and every one of them repeats the reply's usage.
    @Test func testReplyWrittenAsSeveralBlocksCountsOnce() {
        setUp()
        defer { tearDown() }
        append([
            reply(id: "msg_1", input: 10, output: 500, block: "thinking"),
            reply(id: "msg_1", input: 10, output: 500, block: "text"),
            reply(id: "msg_1", input: 10, output: 500, block: "tool_use"),
        ])
        #expect((TranscriptReader.newUsageTokens(at: path)) == (510))
    }

    @Test func testReplyBlocksSplitAcrossReadsCountOnce() {
        setUp()
        defer { tearDown() }
        append([reply(id: "msg_1", input: 10, output: 500)])
        #expect((TranscriptReader.newUsageTokens(at: path)) == (510))
        append([
            reply(id: "msg_1", input: 10, output: 500, block: "tool_use"),
            reply(id: "msg_2", input: 5, output: 20),
        ])
        #expect((TranscriptReader.newUsageTokens(at: path)) == (25))
    }

    /// Resuming a session copies its replies into a new transcript file.
    @Test func testReplyCopiedIntoAnotherTranscriptCountsOnce() throws {
        setUp()
        defer { tearDown() }
        let other = NSTemporaryDirectory() + "agentpet-usage-\(UUID().uuidString).jsonl"
        defer { try? FileManager.default.removeItem(atPath: other) }
        append([reply(id: "msg_1", input: 0, output: 300)])
        #expect((TranscriptReader.newUsageTokens(at: path)) == (300))
        try (reply(id: "msg_1", input: 0, output: 300) + "\n" + reply(id: "msg_2", input: 0, output: 7) + "\n")
            .write(toFile: other, atomically: true, encoding: .utf8)
        #expect((TranscriptReader.newUsageTokens(at: other)) == (7))
    }

    @Test func testCostCountsTheReplyOnceToo() {
        setUp()
        defer { tearDown() }
        append([
            reply(id: "msg_1", input: 1_000_000, output: 0, block: "thinking"),
            reply(id: "msg_1", input: 1_000_000, output: 0, block: "text"),
        ])
        let delta = TranscriptReader.newUsageDelta(at: path)
        #expect((delta?.tokens) == (1_000_000))
        let once = ModelPricing.costUSD(model: nil, inputTokens: 1_000_000, outputTokens: 0,
                                        cacheCreateTokens: 0, cacheReadTokens: 0)
        #expect(abs((delta?.costUSD ?? 0) - (once)) <= 1e-9)
    }

    /// After a relaunch every transcript is read from the start again, and a
    /// resumed session copies earlier replies into its new file: usage written
    /// before counting started must not be eaten (again).
    @Test func testUsageWrittenBeforeCountingStartedIsSkipped() {
        setUp()
        defer { tearDown() }
        TranscriptReader.countUsageSince = ISO8601DateFormatter().date(from: "2026-10-22T12:00:00Z")
        defer { TranscriptReader.countUsageSince = nil }
        append([
            reply(id: "msg_old", at: "2026-10-21T09:00:00.000Z", input: 0, output: 9_000),
            reply(id: "msg_new", at: "2026-10-22T12:30:00.000Z", input: 0, output: 40),
            assistantLine(input: 1, output: 1),   // no timestamp: still counted
        ])
        #expect((TranscriptReader.newUsageTokens(at: path)) == (42))
    }
}
