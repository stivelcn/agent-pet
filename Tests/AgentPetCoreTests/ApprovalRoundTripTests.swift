import Testing
import Foundation
@testable import AgentPetCore

/// Phase 2 approve/deny round trip over the socket, plus the CLI hook's JSON helper.
@Suite(.serialized)
final class ApprovalRoundTripTests {
    private final class Box<T>: @unchecked Sendable {
        var value: T?
    }

    private func makeApprovalEvent(requestId: String) -> AgentEvent {
        AgentEvent(
            sessionId: "s1", agentKind: .claude, eventName: "PreToolUse",
            approvalRequestId: requestId, toolName: "Bash", toolSummary: "rm -rf /tmp/x",
            timestamp: Date(timeIntervalSince1970: 1)
        )
    }

    @Test func testApproveRoundTrip() throws {
        let path = "/tmp/agentpet-\(UUID().uuidString).sock"
        let server = EventSocketServer(path: path)
        defer { server.stop() }

        let requestId = "req-approve-\(UUID().uuidString)"
        let eventReceived = TestSignal(description: "onEvent invoked")
        try server.start { event in
            #expect((event.approvalRequestId) == (requestId))
            PendingApprovalRegistry.shared.resolve(requestId: requestId, decision: .allow)
            eventReceived.fulfill()
        }

        let event = makeApprovalEvent(requestId: requestId)
        let resultBox = Box<ApprovalDecision>()
        let replyReceived = TestSignal(description: "reply received")
        DispatchQueue.global().async {
            resultBox.value = EventSender.sendAndAwaitReply(event, socketPath: path, timeout: 5)
            replyReceived.fulfill()
        }

        waitForSignals( [eventReceived, replyReceived], timeout: 5)
        #expect((resultBox.value) == (.allow))
    }

    @Test func testDenyRoundTrip() throws {
        let path = "/tmp/agentpet-\(UUID().uuidString).sock"
        let server = EventSocketServer(path: path)
        defer { server.stop() }

        let requestId = "req-deny-\(UUID().uuidString)"
        let eventReceived = TestSignal(description: "onEvent invoked")
        try server.start { event in
            PendingApprovalRegistry.shared.resolve(requestId: requestId, decision: .deny)
            eventReceived.fulfill()
        }

        let event = makeApprovalEvent(requestId: requestId)
        let resultBox = Box<ApprovalDecision>()
        let replyReceived = TestSignal(description: "reply received")
        DispatchQueue.global().async {
            resultBox.value = EventSender.sendAndAwaitReply(event, socketPath: path, timeout: 5)
            replyReceived.fulfill()
        }

        waitForSignals( [eventReceived, replyReceived], timeout: 5)
        #expect((resultBox.value) == (.deny))
    }

    @Test func testTimeoutReturnsAskWithoutHanging() throws {
        let path = "/tmp/agentpet-\(UUID().uuidString).sock"
        let server = EventSocketServer(path: path)
        defer { server.stop() }

        let requestId = "req-timeout-\(UUID().uuidString)"
        let eventReceived = TestSignal(description: "onEvent invoked")
        // Deliberately never resolve this request; the client must time out on its own.
        try server.start { _ in eventReceived.fulfill() }

        let event = makeApprovalEvent(requestId: requestId)
        let resultBox = Box<ApprovalDecision>()
        let replyReceived = TestSignal(description: "reply received")
        DispatchQueue.global().async {
            resultBox.value = EventSender.sendAndAwaitReply(event, socketPath: path, timeout: 1)
            replyReceived.fulfill()
        }

        waitForSignals( [eventReceived, replyReceived], timeout: 3)
        #expect((resultBox.value) == (.ask))
    }

    @Test func testNoDaemonReturnsAskImmediately() {
        let path = "/tmp/agentpet-\(UUID().uuidString).sock" // nothing listening here
        let start = Date()
        let decision = EventSender.sendAndAwaitReply(
            makeApprovalEvent(requestId: "req-no-daemon"), socketPath: path, timeout: 5
        )
        #expect((decision) == (.ask))
        #expect((Date().timeIntervalSince(start)) < (2), Comment(rawValue: "connect failure must not wait for the timeout"))
    }

    @Test func testNonApprovalEventClosesConnectionAfterSend() throws {
        let path = "/tmp/agentpet-\(UUID().uuidString).sock"
        let server = EventSocketServer(path: path)
        defer { server.stop() }

        let eventReceived = TestSignal(description: "onEvent invoked")
        let box = Box<AgentEvent>()
        try server.start { event in
            box.value = event
            eventReceived.fulfill()
        }

        let event = AgentEvent(
            sessionId: "s-plain", agentKind: .claude, eventName: "Stop",
            timestamp: Date(timeIntervalSince1970: 42)
        )
        let dir = NSTemporaryDirectory() + "agentpet-q-\(UUID().uuidString)"
        let delivered = EventSender.send(event, socketPath: path, queueDir: dir)

        waitForSignals( [eventReceived], timeout: 5)
        #expect(delivered, Comment(rawValue: "socket path exists, must deliver over the socket (not fall back to queue)"))
        #expect((box.value?.approvalRequestId) == (nil))
        #expect((box.value) == (event))
    }

    /// Root cause of the old flaky `testApproveRoundTrip`: on macOS,
    /// setting SO_RCVTIMEO on a socket whose peer already replied and closed
    /// fails with EINVAL. `sendAndAwaitReply` must therefore set it before
    /// writing, while the peer can't have replied yet. This pins the OS
    /// behaviour the ordering depends on.
    @Test func testReceiveTimeoutFailsOncePeerHasClosed() {
        var fds: [Int32] = [0, 0]
        fds.withUnsafeMutableBufferPointer { _ = socketpair(AF_UNIX, SOCK_STREAM, 0, $0.baseAddress) }
        defer { close(fds[0]) }
        var tv = timeval(tv_sec: 1, tv_usec: 0)
        let size = socklen_t(MemoryLayout<timeval>.size)
        #expect((setsockopt(fds[0], SOL_SOCKET, SO_RCVTIMEO, &tv, size)) == (0), Comment(rawValue: "peer open: must succeed"))

        _ = Data("x\n".utf8).withUnsafeBytes { write(fds[1], $0.baseAddress, $0.count) }
        close(fds[1])
        #expect((setsockopt(fds[0], SOL_SOCKET, SO_RCVTIMEO, &tv, size)) != (0), Comment(rawValue: "peer closed: macOS rejects SO_RCVTIMEO"))
    }

    @Test func testApprovalResponseJSONForAllow() throws {
        try assertApprovalResponseJSON(.allow, expectedPermissionDecision: "allow")
    }

    @Test func testApprovalResponseJSONForDeny() throws {
        try assertApprovalResponseJSON(.deny, expectedPermissionDecision: "deny")
    }

    @Test func testApprovalResponseJSONForAsk() throws {
        try assertApprovalResponseJSON(.ask, expectedPermissionDecision: "ask")
    }

    private func assertApprovalResponseJSON(
        _ decision: ApprovalDecision, expectedPermissionDecision: String,
        sourceLocation: SourceLocation = #_sourceLocation
    ) throws {
        let json = ApprovalHookResponse.json(for: decision)
        let data = try #require(json.data(using: .utf8), sourceLocation: sourceLocation)
        let parsed = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let hookSpecificOutput = try #require(parsed?["hookSpecificOutput"] as? [String: Any], sourceLocation: sourceLocation)
        #expect((hookSpecificOutput["hookEventName"] as? String) == ("PreToolUse"), sourceLocation: sourceLocation)
        #expect((hookSpecificOutput["permissionDecision"] as? String) == (expectedPermissionDecision), sourceLocation: sourceLocation)
    }
}
