import Testing
import Foundation
@testable import AgentPetCore

@Suite(.serialized)
final class JcodeClaudeAuthTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private var futureMs: Double { (now.timeIntervalSince1970 + 3600) * 1000 }
    private var pastMs: Double { (now.timeIntervalSince1970 - 60) * 1000 }

    private func auth(_ accounts: [[String: Any]], active: String?) -> Data {
        var json: [String: Any] = ["anthropic_accounts": accounts]
        if let active { json["active_anthropic_account"] = active }
        return try! JSONSerialization.data(withJSONObject: json)
    }

    @Test func testActiveAccountWins() {
        let data = auth([
            ["label": "a", "access": "tok-a", "expires": futureMs],
            ["label": "b", "access": "tok-b", "expires": futureMs],
        ], active: "b")
        #expect((JcodeClaudeAuth.accessToken(fromAuthJSON: data, now: now)) == ("tok-b"))
    }

    @Test func testFallsBackToFirstAccountWhenActiveUnknown() {
        let data = auth([["label": "a", "access": "tok-a", "expires": futureMs]], active: "gone")
        #expect((JcodeClaudeAuth.accessToken(fromAuthJSON: data, now: now)) == ("tok-a"))
        let noActive = auth([["label": "a", "access": "tok-a", "expires": futureMs]], active: nil)
        #expect((JcodeClaudeAuth.accessToken(fromAuthJSON: noActive, now: now)) == ("tok-a"))
    }

    @Test func testExpiredTokenIsSkipped() {
        let data = auth([["label": "a", "access": "tok-a", "expires": pastMs]], active: "a")
        #expect((JcodeClaudeAuth.accessToken(fromAuthJSON: data, now: now)) == nil)
    }

    @Test func testMalformedOrEmptyIsNil() {
        #expect((JcodeClaudeAuth.accessToken(fromAuthJSON: Data("not json".utf8), now: now)) == nil)
        #expect((JcodeClaudeAuth.accessToken(fromAuthJSON: Data("{}".utf8), now: now)) == nil)
        #expect((JcodeClaudeAuth.accessToken(fromAuthJSON: auth([], active: nil), now: now)) == nil)
        let blank = auth([["label": "a", "access": "", "expires": futureMs]], active: "a")
        #expect((JcodeClaudeAuth.accessToken(fromAuthJSON: blank, now: now)) == nil)
    }

    @Test func testExpiryUnits() {
        let t = now.timeIntervalSince1970
        #expect(OAuthExpiry.isExpired(NSNumber(value: (t - 1) * 1000), now: now), Comment(rawValue: "ms, past"))
        #expect(!(OAuthExpiry.isExpired(NSNumber(value: (t + 60) * 1000), now: now)), Comment(rawValue: "ms, future"))
        #expect(OAuthExpiry.isExpired(NSNumber(value: t - 1), now: now), Comment(rawValue: "seconds, past"))
        #expect(!(OAuthExpiry.isExpired(NSNumber(value: t + 60), now: now)), Comment(rawValue: "seconds, future"))
        #expect(!(OAuthExpiry.isExpired(nil, now: now)), Comment(rawValue: "unknown expiry: let the API decide"))
        #expect(!(OAuthExpiry.isExpired("soon", now: now)))
    }
}
