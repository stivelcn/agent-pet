import Testing
import Foundation
@testable import agentpet

@MainActor
@Suite(.serialized)
final class ReactiveEngineTests {

    private func makeEngine() -> ReactiveEngine {
        ReactiveEngine()
    }

    @Test func testRateLimitAbove50PercentIsSilent() {
        let engine = makeEngine()
        let result = engine.evaluate(metric: .rateLimit, value: 0.6)
        #expect((result) == nil)
    }

    @Test func testRateLimitBetween15And50PercentIsLow() {
        let engine = makeEngine()
        let result = engine.evaluate(metric: .rateLimit, value: 0.30)
        #expect((result) != nil)
    }

    @Test func testRateLimitBetween5And15PercentIsHigh() {
        let engine = makeEngine()
        let result = engine.evaluate(metric: .rateLimit, value: 0.10)
        #expect((result) != nil)
    }

    @Test func testRateLimitBelow5PercentIsCritical() {
        let engine = makeEngine()
        let result = engine.evaluate(metric: .rateLimit, value: 0.03)
        #expect((result) != nil)
    }

    @Test func testRateLimitNilValueReturnsSilent() {
        let engine = makeEngine()
        let result = engine.evaluate(metric: .rateLimit, value: nil as Double?)
        #expect((result) == nil)
    }

    @Test func testDailyTokensBelow1MIsSilent() {
        let engine = makeEngine()
        let result = engine.evaluate(metric: .dailyTokens, value: 800_000)
        #expect((result) == nil)
    }

    @Test func testDailyTokensBetween1MAnd3MIsLow() {
        let engine = makeEngine()
        let result = engine.evaluate(metric: .dailyTokens, value: 2_000_000)
        #expect((result) != nil)
    }

    @Test func testDailyTokensBetween3MAnd6MIsMid() {
        let engine = makeEngine()
        let result = engine.evaluate(metric: .dailyTokens, value: 4_500_000)
        #expect((result) != nil)
    }

    @Test func testDailyTokensAbove6MIsHigh() {
        let engine = makeEngine()
        let result = engine.evaluate(metric: .dailyTokens, value: 7_000_000)
        #expect((result) != nil)
    }

    @Test func testSessionCount1To4IsSilent() {
        let engine = makeEngine()
        let result = engine.evaluate(metric: .sessionCount, value: 3)
        #expect((result) == nil)
    }

    @Test func testSessionCount5To7IsLow() {
        let engine = makeEngine()
        let result = engine.evaluate(metric: .sessionCount, value: 6)
        #expect((result) != nil)
    }

    @Test func testSessionCount8OrMoreIsHigh() {
        let engine = makeEngine()
        let result = engine.evaluate(metric: .sessionCount, value: 8)
        #expect((result) != nil)
    }

    @Test func testHungerFullIsSilent() {
        let engine = makeEngine()
        let result = engine.evaluate(metric: .hunger, value: PetHunger.full)
        #expect((result) == nil)
    }

    @Test func testHungerSatisfiedIsSilent() {
        let engine = makeEngine()
        let result = engine.evaluate(metric: .hunger, value: PetHunger.satisfied)
        #expect((result) == nil)
    }

    @Test func testHungerPeckishIsLow() {
        let engine = makeEngine()
        let result = engine.evaluate(metric: .hunger, value: PetHunger.peckish)
        #expect((result) != nil)
    }

    @Test func testHungerHungryIsMid() {
        let engine = makeEngine()
        let result = engine.evaluate(metric: .hunger, value: PetHunger.hungry)
        #expect((result) != nil)
    }

    @Test func testHungerStarvingIsHigh() {
        let engine = makeEngine()
        let result = engine.evaluate(metric: .hunger, value: PetHunger.starving)
        #expect((result) != nil)
    }

    @Test func testStreak1To3IsSilent() {
        let engine = makeEngine()
        let result = engine.evaluate(metric: .streak, value: 2)
        #expect((result) == nil)
    }

    @Test func testStreak4To6IsLow() {
        let engine = makeEngine()
        let result = engine.evaluate(metric: .streak, value: 5)
        #expect((result) != nil)
    }

    @Test func testStreak7To13IsMid() {
        let engine = makeEngine()
        let result = engine.evaluate(metric: .streak, value: 10)
        #expect((result) != nil)
    }

    @Test func testStreak14OrMoreIsHigh() {
        let engine = makeEngine()
        let result = engine.evaluate(metric: .streak, value: 14)
        #expect((result) != nil)
    }

    @Test func testDailyMealsBelow20IsSilent() {
        let engine = makeEngine()
        let result = engine.evaluate(metric: .dailyMeals, value: 10)
        #expect((result) == nil)
    }

    @Test func testDailyMeals20To50IsLow() {
        let engine = makeEngine()
        let result = engine.evaluate(metric: .dailyMeals, value: 35)
        #expect((result) != nil)
    }

    @Test func testDailyMeals50To100IsMid() {
        let engine = makeEngine()
        let result = engine.evaluate(metric: .dailyMeals, value: 75)
        #expect((result) != nil)
    }

    @Test func testDailyMeals100OrMoreIsHigh() {
        let engine = makeEngine()
        let result = engine.evaluate(metric: .dailyMeals, value: 100)
        #expect((result) != nil)
    }

    @Test func testSameMetricBlockedWithin600Seconds() {
        let engine = makeEngine()
        let now = Date(timeIntervalSince1970: 1_000_000)
        let first = engine.evaluate(metric: .dailyTokens, value: 2_000_000, now: now)
        #expect((first) != nil)
        let secondNow = now.addingTimeInterval(599)
        let second = engine.evaluate(metric: .dailyTokens, value: 2_000_000, now: secondNow)
        #expect((second) == nil)
    }

    @Test func testSameMetricAllowedAfter600Seconds() {
        let engine = makeEngine()
        let now = Date(timeIntervalSince1970: 1_000_000)
        engine.evaluate(metric: .dailyTokens, value: 2_000_000, now: now)
        let laterNow = now.addingTimeInterval(600)
        let result = engine.evaluate(metric: .dailyTokens, value: 2_000_000, now: laterNow)
        #expect((result) != nil)
    }

    @Test func testCrossMetricBlockedWithin30Seconds() {
        let engine = makeEngine()
        let now = Date(timeIntervalSince1970: 1_000_000)
        engine.evaluate(metric: .dailyTokens, value: 2_000_000, now: now)
        let laterNow = now.addingTimeInterval(29)
        let result = engine.evaluate(metric: .sessionCount, value: 6, now: laterNow)
        #expect((result) == nil)
    }

    @Test func testCrossMetricAllowedAfter30Seconds() {
        let engine = makeEngine()
        let now = Date(timeIntervalSince1970: 1_000_000)
        engine.evaluate(metric: .dailyTokens, value: 2_000_000, now: now)
        let laterNow = now.addingTimeInterval(30)
        let result = engine.evaluate(metric: .sessionCount, value: 6, now: laterNow)
        #expect((result) != nil)
    }

    @Test func testSameMetricGateTakesPriorityOverCrossMetricGate() {
        let engine = makeEngine()
        let now = Date(timeIntervalSince1970: 1_000_000)
        engine.evaluate(metric: .dailyTokens, value: 2_000_000, now: now)
        let laterNow = now.addingTimeInterval(35)
        let result = engine.evaluate(metric: .dailyTokens, value: 2_000_000, now: laterNow)
        #expect((result) == nil)
    }

    @Test func testHungerDailyLimitBlocksThirdTriggerSameDay() {
        let engine = makeEngine()
        let base = Date(timeIntervalSince1970: 1_750_000_000)
        let t1 = engine.evaluate(metric: .hunger, value: PetHunger.hungry, now: base)
        #expect((t1) != nil)
        let t2 = engine.evaluate(metric: .hunger, value: PetHunger.hungry, now: base.addingTimeInterval(600))
        #expect((t2) != nil)
        let t3 = engine.evaluate(metric: .hunger, value: PetHunger.hungry, now: base.addingTimeInterval(1200))
        #expect((t3) == nil)
    }

    @Test func testHungerDailyLimitResetsNextDay() {
        let engine = makeEngine()
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        formatter.timeZone = TimeZone(identifier: "UTC")
        let day1 = formatter.date(from: "2026-06-17 10:00")!
        let day2 = formatter.date(from: "2026-06-18 10:00")!
        engine.evaluate(metric: .hunger, value: PetHunger.hungry, now: day1)
        engine.evaluate(metric: .hunger, value: PetHunger.hungry, now: day1.addingTimeInterval(600))
        let blocked = engine.evaluate(metric: .hunger, value: PetHunger.hungry, now: day1.addingTimeInterval(1200))
        #expect((blocked) == nil)
        let tomorrow = engine.evaluate(metric: .hunger, value: PetHunger.hungry, now: day2)
        #expect((tomorrow) != nil)
    }

    @Test func testSilentTierReturnsNil() {
        let engine = makeEngine()
        let result = engine.evaluate(metric: .rateLimit, value: 0.9)
        #expect((result) == nil)
    }

    @Test func testNonSilentTierReturnsNonNilString() {
        let engine = makeEngine()
        let result = engine.evaluate(metric: .streak, value: 14)
        #expect((result) != nil)
        #expect(!(result?.isEmpty ?? true))
    }

    @Test func testNilValueReturnsNil() {
        let engine = makeEngine()
        let result = engine.evaluate(metric: .rateLimit, value: nil as Double?)
        #expect((result) == nil)
    }

    @Test func testCooldownBlockReturnsNil() {
        let engine = makeEngine()
        let now = Date(timeIntervalSince1970: 1_000_000)
        let first = engine.evaluate(metric: .streak, value: 14, now: now)
        #expect((first) != nil)
        let second = engine.evaluate(metric: .streak, value: 14, now: now.addingTimeInterval(1))
        #expect((second) == nil)
    }
}

private extension ReactiveEngine {
    @discardableResult
    func evaluate(metric: ReactiveMetric, value: Double?, now: Date = .now) -> String? {
        evaluate(metric: metric, value: value.map { AnyHashable($0) }, now: now)
    }

    @discardableResult
    func evaluate(metric: ReactiveMetric, value: Double, now: Date = .now) -> String? {
        evaluate(metric: metric, value: AnyHashable(value), now: now)
    }

    @discardableResult
    func evaluate(metric: ReactiveMetric, value: Int, now: Date = .now) -> String? {
        evaluate(metric: metric, value: AnyHashable(value), now: now)
    }

    @discardableResult
    func evaluate(metric: ReactiveMetric, value: PetHunger, now: Date = .now) -> String? {
        evaluate(metric: metric, value: AnyHashable(value), now: now)
    }
}
