import Testing
import Foundation
@testable import AgentPetCore

@Suite(.serialized)
final class TranscriptReaderLatestAssistantTextTests {
    private func tempTranscript(_ lines: [String]) throws -> String {
        let path = NSTemporaryDirectory() + "transcript-\(UUID().uuidString).jsonl"
        try Data(lines.joined(separator: "\n").utf8).write(to: URL(fileURLWithPath: path))
        return path
    }

    private func assistantLine(_ text: String) -> String {
        let escaped = text.replacingOccurrences(of: "\"", with: "\\\"")
        return #"{"type":"assistant","message":{"content":[{"type":"text","text":"\#(escaped)"}]}}"#
    }

    private let userLine = #"{"type":"user","message":{"content":[{"type":"text","text":"thanks"}]}}"#

    @Test func testReturnsLatestAssistantTextVerbatim() throws {
        let path = try tempTranscript([
            assistantLine("Working on it now."),
            userLine,
            assistantLine("Which approach do you want — A or B?")
        ])
        defer { try? FileManager.default.removeItem(atPath: path) }

        #expect((TranscriptReader.latestAssistantText(at: path)) == ("Which approach do you want — A or B?"))
    }

    @Test func testSkipsTrailingNonAssistantLines() throws {
        let path = try tempTranscript([
            assistantLine("All done — pushed the fix."),
            userLine
        ])
        defer { try? FileManager.default.removeItem(atPath: path) }

        #expect((TranscriptReader.latestAssistantText(at: path)) == ("All done — pushed the fix."))
    }

    @Test func testReturnsNilForUnreadablePath() {
        #expect((TranscriptReader.latestAssistantText(at: "/no/such/file-\(UUID().uuidString).jsonl")) == nil)
    }

    @Test func testReturnsNilWhenNoAssistantLineExists() throws {
        let path = try tempTranscript([userLine])
        defer { try? FileManager.default.removeItem(atPath: path) }

        #expect((TranscriptReader.latestAssistantText(at: path)) == nil)
    }

    private func assistantLine(model: String) -> String {
        #"{"type":"assistant","message":{"model":"\#(model)","content":[{"type":"text","text":"hi"}]}}"#
    }

    @Test func testLatestAssistantModelReturnsMostRecent() throws {
        let path = try tempTranscript([
            assistantLine(model: "claude-sonnet-4-6"),
            userLine,
            assistantLine(model: "claude-opus-4-1-20250805")
        ])
        defer { try? FileManager.default.removeItem(atPath: path) }

        #expect((TranscriptReader.latestAssistantModel(at: path)) == ("claude-opus-4-1-20250805"))
    }

    @Test func testLatestAssistantModelNilWhenAbsent() throws {
        let path = try tempTranscript([userLine])
        defer { try? FileManager.default.removeItem(atPath: path) }

        #expect((TranscriptReader.latestAssistantModel(at: path)) == nil)
    }
}
