import Testing
import Foundation
@testable import agentpet

@Suite(.serialized)
final class IdleBoostTests {
    @Test func testLinesKeepPolishedDeveloperTone() {
        #expect(IdleBoost.lines.contains("Let's grill some bugs."))
        #expect(IdleBoost.lines.contains("I miss you. Open a branch for me."))
        #expect(IdleBoost.lines.contains("Tiny commit, tiny dopamine."))
    }

    @Test func testLinesAvoidNoisyPunctuationAndEmoji() {
        for line in IdleBoost.lines {
            #expect(!(line.contains("!")), Comment(rawValue: line))
            let isASCII = line.allSatisfy(\.isASCII)
            #expect(isASCII, Comment(rawValue: line))
        }
    }

    @Test func testLineSelectionIsStableInsideSameMinute() {
        let now = Date(timeIntervalSince1970: 120)

        #expect((IdleBoost.line(at: now)) == (IdleBoost.line(at: now.addingTimeInterval(59))))
    }

    @Test func testLineSelectionRotatesAcrossMinutes() {
        let first = IdleBoost.line(at: Date(timeIntervalSince1970: 0))
        let later = IdleBoost.line(at: Date(timeIntervalSince1970: 60))

        #expect((first) != (later))
    }
}
