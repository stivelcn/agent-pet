import Testing
import Foundation
@testable import AgentPetCore

@Suite(.serialized)
final class HookArgumentsTests {
    @Test func testParseAllFlags() {
        let args = ["--event", "Stop", "--session", "s1", "--project", "/p",
                    "--agent", "claude", "--message", "hello world"]
        let parsed = HookArguments.parse(args)
        #expect((parsed) == (HookArguments(
            event: "Stop", session: "s1", project: "/p", agent: "claude", message: "hello world"
        )))
    }

    @Test func testParseIgnoresUnknownFlags() {
        let parsed = HookArguments.parse(["--bogus", "x", "--event", "Stop", "--session", "s1"])
        #expect((parsed.event) == ("Stop"))
        #expect((parsed.session) == ("s1"))
    }

    @Test func testMakeEventRequiresEventAndSession() {
        let now = Date(timeIntervalSince1970: 1)
        #expect((HookArguments(event: "Stop").makeEvent(now: now)) == nil)
        #expect((HookArguments(session: "s1").makeEvent(now: now)) == nil)
    }

    @Test func testMakeEventDefaultsToClaude() {
        let now = Date(timeIntervalSince1970: 1)
        let event = HookArguments(event: "Stop", session: "s1").makeEvent(now: now)
        #expect((event?.agentKind) == (.claude))
        #expect((event?.eventName) == ("Stop"))
        #expect((event?.timestamp) == (now))
    }
}

@Suite(.serialized)
final class RunArgumentsTests {
    @Test func testParsesFlagsThenCommand() {
        let parsed = RunArguments.parse(["--session", "s1", "--project", "/p", "--agent", "cli", "--", "aider", "--model", "gpt"])
        #expect((parsed) == (RunArguments(session: "s1", project: "/p", agent: "cli", command: ["aider", "--model", "gpt"])))
    }

    @Test func testNoFlagsJustCommand() {
        let parsed = RunArguments.parse(["--", "claude"])
        #expect((parsed.command) == (["claude"]))
        #expect((parsed.session) == nil)
    }

    @Test func testNoCommand() {
        #expect(RunArguments.parse(["--session", "x"]).command.isEmpty)
    }
}

@Suite(.serialized)
final class EventSenderTests {
    @Test func testSenderDeliversOverSocket() throws {
        let path = "/tmp/agentpet-\(UUID().uuidString).sock"
        let server = EventSocketServer(path: path)
        defer { server.stop() }

        let exp = TestSignal(description: "delivered")
        let box = Box()
        try server.start { box.value = $0; exp.fulfill() }

        let event = AgentEvent(sessionId: "s9", agentKind: .claude, eventName: "Notification",
                               timestamp: Date(timeIntervalSince1970: 42))
        let delivered = EventSender.send(event, socketPath: path, queueDir: "/tmp/unused-\(UUID().uuidString)")

        waitForSignals( [exp], timeout: 2)
        #expect(delivered)
        #expect((box.value) == (event))
    }

    @Test func testSenderFallsBackToQueueWhenNoServer() throws {
        let socketPath = "/tmp/agentpet-missing-\(UUID().uuidString).sock"
        let queueDir = NSTemporaryDirectory() + "agentpet-q-\(UUID().uuidString)"
        defer { try? FileManager.default.removeItem(atPath: queueDir) }

        let event = AgentEvent(sessionId: "s10", agentKind: .claude, eventName: "Stop",
                               timestamp: Date(timeIntervalSince1970: 7))
        let delivered = EventSender.send(event, socketPath: socketPath, queueDir: queueDir)
        #expect(!(delivered), Comment(rawValue: "no server, should queue"))

        var received: [AgentEvent] = []
        EventSocketServer.drainQueue(directory: queueDir) { received.append($0) }
        #expect((received) == ([event]))
    }

    private final class Box: @unchecked Sendable {
        var value: AgentEvent?
    }
}
