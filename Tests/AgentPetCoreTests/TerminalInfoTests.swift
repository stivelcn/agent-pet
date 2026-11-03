import Testing
import Foundation
@testable import AgentPetCore

@Suite(.serialized)
final class TerminalInfoTests {
    @Test func testCaptureReadsTermProgramFromEnv() {
        let c = TerminalInfo.capture(env: ["TERM_PROGRAM": "WarpTerminal"])
        #expect((c.program) == ("WarpTerminal"))
    }

    @Test func testCaptureTreatsMissingTermProgramAsNil() {
        #expect((TerminalInfo.capture(env: [:]).program) == nil)
    }

    @Test func testCaptureTreatsEmptyTermProgramAsNil() {
        #expect((TerminalInfo.capture(env: ["TERM_PROGRAM": ""]).program) == nil, Comment(rawValue: "an empty TERM_PROGRAM should disable the affordance, not enable it"))
    }

    @Test func testCaptureReadsWarpFocusURL() {
        let c = TerminalInfo.capture(env: [
            "TERM_PROGRAM": "WarpTerminal",
            "WARP_FOCUS_URL": "warp://session/abc123",
        ])
        #expect((c.focusURL) == ("warp://session/abc123"))
    }

    @Test func testCaptureFocusURLNilWhenAbsent() {
        #expect((TerminalInfo.capture(env: ["TERM_PROGRAM": "Apple_Terminal"]).focusURL) == nil)
    }

    /// `procInfo` must agree with `ps`, which it replaced for the ancestor walk.
    @Test func testProcInfoMatchesPS() throws {
        let pid = getpid()
        let info = try #require(TerminalInfo.procInfo(pid: pid))
        #expect((info.ppid) == (getppid()))

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-o", "tty=", "-p", "\(pid)"]
        let pipe = Pipe()
        process.standardOutput = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let ps = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        #expect((info.tty) == (ps == "??" ? nil : "/dev/\(ps)"))
    }

    @Test func testProcInfoNilForMissingProcess() {
        #expect((TerminalInfo.procInfo(pid: 99_999_999)) == nil)
    }
}
