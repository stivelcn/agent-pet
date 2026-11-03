// Tests/AgentPetCoreTests/BreakClockTests.swift
import Testing
import Foundation
@testable import AgentPetCore

@Suite(.serialized)
final class BreakClockTests {
    private let t0 = Date(timeIntervalSince1970: 0)
    private func cfg(enabled: Bool = true, work: TimeInterval, brk: TimeInterval,
                     maxDelta: TimeInterval = 300) -> BreakClockConfig {
        BreakClockConfig(enabled: enabled, workInterval: work, breakLength: brk, maxDelta: maxDelta)
    }

    @Test func testFiresBreakDueAfterWorkInterval() {
        let c = BreakClock()
        let k = cfg(work: 120, brk: 30)
        #expect((c.tick(now: t0, isPresent: true, config: k)) == (.none))        // active 0
        #expect((c.tick(now: t0.addingTimeInterval(60), isPresent: true, config: k)) == (.none))  // active 60
        #expect((c.tick(now: t0.addingTimeInterval(120), isPresent: true, config: k)) == (.breakDue)) // active 120
    }

    @Test func testAbsenceResetsClockSoNoNagAfterLunch() {
        let c = BreakClock()
        let k = cfg(work: 120, brk: 30)
        _ = c.tick(now: t0, isPresent: true, config: k)                       // active 0
        _ = c.tick(now: t0.addingTimeInterval(60), isPresent: true, config: k) // active 60
        _ = c.tick(now: t0.addingTimeInterval(75), isPresent: false, config: k) // absence 15
        _ = c.tick(now: t0.addingTimeInterval(90), isPresent: false, config: k) // absence 30 → reset
        // back, present again: clock restarted, must NOT be due
        #expect((c.tick(now: t0.addingTimeInterval(105), isPresent: true, config: k)) == (.none))
    }

    @Test func testFiresBreakOverAfterBreakLength() {
        let c = BreakClock()
        let k = cfg(work: 60, brk: 30)
        _ = c.tick(now: t0, isPresent: true, config: k)                        // active 0
        #expect((c.tick(now: t0.addingTimeInterval(60), isPresent: true, config: k)) == (.breakDue)) // resting since +60
        #expect((c.tick(now: t0.addingTimeInterval(80), isPresent: true, config: k)) == (.none))     // 20 < 30
        #expect((c.tick(now: t0.addingTimeInterval(90), isPresent: true, config: k)) == (.breakOver)) // 30 >= 30
    }

    @Test func testHugeDeltaResetsAndDoesNotFire() {
        let c = BreakClock()
        let k = cfg(work: 120, brk: 30, maxDelta: 300)
        _ = c.tick(now: t0, isPresent: true, config: k)
        _ = c.tick(now: t0.addingTimeInterval(60), isPresent: true, config: k)  // active 60
        // machine slept 600s > maxDelta → reset, no break
        #expect((c.tick(now: t0.addingTimeInterval(660), isPresent: true, config: k)) == (.none))
        _ = c.tick(now: t0.addingTimeInterval(720), isPresent: true, config: k) // active 60
        #expect((c.tick(now: t0.addingTimeInterval(780), isPresent: true, config: k)) == (.breakDue)) // active 120
    }

    @Test func testDisabledNeverFires() {
        let c = BreakClock()
        let k = cfg(enabled: false, work: 1, brk: 1)
        #expect((c.tick(now: t0, isPresent: true, config: k)) == (.none))
        #expect((c.tick(now: t0.addingTimeInterval(10_000), isPresent: true, config: k)) == (.none))
    }

    @Test func testIntervalShrinkMidFlightFiresNextTick() {
        let c = BreakClock()
        var k = cfg(work: 600, brk: 30)
        _ = c.tick(now: t0, isPresent: true, config: k)
        _ = c.tick(now: t0.addingTimeInterval(60), isPresent: true, config: k)   // active 60
        _ = c.tick(now: t0.addingTimeInterval(120), isPresent: true, config: k)  // active 120
        k.workInterval = 100
        #expect((c.tick(now: t0.addingTimeInterval(180), isPresent: true, config: k)) == (.breakDue)) // 180 >= 100
    }

    @Test func testShortAbsenceKeepsAccumulatedTime() {
        let c = BreakClock()
        let k = cfg(work: 120, brk: 60)
        _ = c.tick(now: t0, isPresent: true, config: k)                         // active 0
        _ = c.tick(now: t0.addingTimeInterval(60), isPresent: true, config: k)  // active 60
        _ = c.tick(now: t0.addingTimeInterval(75), isPresent: false, config: k) // absence 15 (<60), active kept
        _ = c.tick(now: t0.addingTimeInterval(90), isPresent: true, config: k)  // active 60+15=75
        #expect((c.tick(now: t0.addingTimeInterval(135), isPresent: true, config: k)) == (.breakDue)) // 75+45=120
    }
}
