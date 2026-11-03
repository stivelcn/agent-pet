import Testing
import Foundation
@testable import AgentPetCore

/// The accept loop must never spin a CPU core at 100% when `accept()` fails
/// repeatedly. `acceptErrorAction` classifies the errno so the loop knows
/// whether to retry, back off, or stop.
@Suite(.serialized)
final class AcceptErrorActionTests {
    @Test func testInterruptedRetriesImmediately() {
        #expect((EventSocketServer.acceptErrorAction(errno: EINTR)) == (.retryImmediately))
    }

    @Test func testConnectionAbortedRetriesImmediately() {
        #expect((EventSocketServer.acceptErrorAction(errno: ECONNABORTED)) == (.retryImmediately))
    }

    @Test func testFileDescriptorExhaustionBacksOff() {
        #expect((EventSocketServer.acceptErrorAction(errno: EMFILE)) == (.backoff))
        #expect((EventSocketServer.acceptErrorAction(errno: ENFILE)) == (.backoff))
    }

    @Test func testBadListenSocketStops() {
        #expect((EventSocketServer.acceptErrorAction(errno: EBADF)) == (.stop))
        #expect((EventSocketServer.acceptErrorAction(errno: EINVAL)) == (.stop))
        #expect((EventSocketServer.acceptErrorAction(errno: ENOTSOCK)) == (.stop))
    }

    @Test func testUnknownErrorBacksOffRatherThanSpinning() {
        // An unrecognised errno must never fall through to a tight retry loop.
        #expect((EventSocketServer.acceptErrorAction(errno: 9999)) == (.backoff))
    }
}
