import Testing
import Foundation
@testable import AgentPetCore

@Suite(.serialized)
final class PerKeyThrottleTests {
    @Test func testFirstCallForKeyRuns() {
        let throttle = PerKeyThrottle(interval: 10)
        let t0 = Date(timeIntervalSince1970: 0)
        #expect(throttle.shouldRun("a", now: t0), Comment(rawValue: "the first call for a key must run"))
    }

    @Test func testSecondCallWithinIntervalIsSkipped() {
        let throttle = PerKeyThrottle(interval: 10)
        let t0 = Date(timeIntervalSince1970: 0)
        _ = throttle.shouldRun("a", now: t0)
        #expect(!(throttle.shouldRun("a", now: t0.addingTimeInterval(9))), Comment(rawValue: "a call before the interval elapses must be skipped"))
    }

    @Test func testCallAfterIntervalRunsAgain() {
        let throttle = PerKeyThrottle(interval: 10)
        let t0 = Date(timeIntervalSince1970: 0)
        _ = throttle.shouldRun("a", now: t0)
        #expect(throttle.shouldRun("a", now: t0.addingTimeInterval(10)), Comment(rawValue: "once the interval has elapsed the key runs again"))
    }

    @Test func testKeysAreIndependent() {
        let throttle = PerKeyThrottle(interval: 10)
        let t0 = Date(timeIntervalSince1970: 0)
        _ = throttle.shouldRun("a", now: t0)
        #expect(throttle.shouldRun("b", now: t0), Comment(rawValue: "throttling one key must not block a different key"))
    }
}
