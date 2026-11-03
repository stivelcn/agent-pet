import Testing
import Foundation
@testable import agentpet

/// Which providers get a row in the Limits sections (HUD and Care tab).
@MainActor
@Suite(.serialized)
final class UsageLimitRowsTests {

    private func provider(_ id: String, left: Double?) -> OpenUsageClient.Provider {
        // No window means no limit, same as the old nil fractionLeft.
        OpenUsageClient.Provider(id: id, displayName: id, plan: nil, todayLabel: nil,
                                 windows: left.map { [.init(label: "Session", fractionLeft: $0)] } ?? [])
    }

    /// A provider with only text lines has no limit, so it gets no row instead
    /// of a full red "100% used" bar.
    @Test func testProviderWithoutLimitIsLeftOut() {
        let rows = NativeUsageProbe.combine(
            native: [provider("claude", left: 0.21)],
            openUsage: [provider("openrouter", left: nil), provider("grok", left: 1)])
        #expect((rows.map(\.id)) == (["claude", "grok"]))
    }

    /// Native probes still win over OpenUsage for the same provider.
    @Test func testNativeProviderWinsOverOpenUsage() {
        let rows = NativeUsageProbe.combine(
            native: [provider("claude", left: 0.21)],
            openUsage: [provider("claude", left: 0.9), provider("copilot", left: 1)])
        #expect((rows.map(\.id)) == (["claude", "copilot"]))
        #expect((rows.first?.fractionLeft) == (0.21))
    }
}
