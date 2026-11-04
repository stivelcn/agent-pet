import Foundation
import Testing
@testable import AgentPetCore

@Suite(.serialized)
struct TranscriptIncrementTests {
    private func withTranscript(_ body: (String) throws -> Void) rethrows {
        let path = NSTemporaryDirectory() + "agentpet-token-test-\(UUID().uuidString).jsonl"
        TranscriptReader.clearCache()
        defer {
            TranscriptReader.clearCache()
            try? FileManager.default.removeItem(atPath: path)
        }
        try body(path)
    }

    private func line(model: String, input: Int, output: Int) -> String {
        #"{"type":"assistant","message":{"model":"\#(model)","usage":{"input_tokens":\#(input),"output_tokens":\#(output),"cache_creation_input_tokens":500,"cache_read_input_tokens":2000}}}"# + "\n"
    }

    @Test func tokensIncludeInputAndOutputWithoutChangingCacheSemantics() throws {
        try withTranscript { path in
            try line(model: "synthetic-model-a", input: 1_000, output: 250)
                .write(toFile: path, atomically: true, encoding: .utf8)
            #expect(TranscriptReader.newUsageTokens(at: path) == 1_250)
        }
    }

    @Test func repeatedScanWithoutNewLinesReturnsZero() throws {
        try withTranscript { path in
            try line(model: "synthetic-model", input: 500, output: 100)
                .write(toFile: path, atomically: true, encoding: .utf8)
            #expect(TranscriptReader.newUsageTokens(at: path) == 600)
            #expect(TranscriptReader.newUsageTokens(at: path) == 0)
        }
    }

    @Test func differentModelsCountTokensWithoutNeedingModelMetadata() throws {
        try withTranscript { path in
            let text = line(model: "synthetic-model-a", input: 1_000, output: 500)
                + line(model: "unknown-model", input: 2_000, output: 1_000)
            try text.write(toFile: path, atomically: true, encoding: .utf8)
            #expect(TranscriptReader.newUsageTokens(at: path) == 4_500)
        }
    }

    @Test func unreadableTranscriptReturnsNil() {
        withTranscript { path in #expect(TranscriptReader.newUsageTokens(at: path) == nil) }
    }

    @Test func clearingCacheRestartsTheTokenScan() throws {
        try withTranscript { path in
            try line(model: "synthetic-model", input: 1_000, output: 250)
                .write(toFile: path, atomically: true, encoding: .utf8)
            #expect(TranscriptReader.newUsageTokens(at: path) == 1_250)
            TranscriptReader.clearCache()
            #expect(TranscriptReader.newUsageTokens(at: path) == 1_250)
        }
    }
}
