import Testing
import Foundation
@testable import AgentPetCore

@Suite(.serialized)
final class PetCareTests {

    private let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    private func date(_ s: String) -> Date {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm"
        f.timeZone = TimeZone(identifier: "UTC")
        return f.date(from: s)!
    }

    // MARK: - Levels

    @Test func testLevelCurve() {
        #expect((PetCare.xpToReach(level: 1)) == (0))
        #expect((PetCare.xpToReach(level: 2)) == (120))
        #expect((PetCare.xpToReach(level: 3)) == (360))
        #expect((PetCare.level(forXP: 0)) == (1))
        #expect((PetCare.level(forXP: 119)) == (1))
        #expect((PetCare.level(forXP: 120)) == (2))
        #expect((PetCare.level(forXP: 5_400)) == (10))
        #expect((PetCare.level(forXP: 71_400)) == (35))
    }

    @Test func testProgressWithinLevel() {
        #expect(abs((PetCare.progress(forXP: 0)) - (0)) <= 0.001)
        #expect(abs((PetCare.progress(forXP: 60)) - (0.5)) <= 0.001)
        #expect(abs((PetCare.progress(forXP: 120)) - (0)) <= 0.001)
    }

    @Test func testStages() {
        #expect((PetCare.stageName(forLevel: 1)) == ("Hatchling"))
        #expect((PetCare.stageName(forLevel: 5)) == ("Companion"))
        #expect((PetCare.stageName(forLevel: 10)) == ("Scout"))
        #expect((PetCare.stageName(forLevel: 20)) == ("Hero"))
        #expect((PetCare.stageName(forLevel: 35)) == ("Legend"))
        #expect((PetCare.stageIndex(forLevel: 1)) == (0))
        #expect((PetCare.stageIndex(forLevel: 99)) == (4))
    }

    // MARK: - Feeding

    @Test func testFeedTokensGrantsXPWithCarry() {
        var s = PetCareState()
        let now = date("2026-06-12 10:00")
        // 12 500 tokens = 2 XP + 2 500 carry
        #expect((PetCare.feedTokens(12_500, state: &s, now: now, calendar: calendar)) == (2))
        #expect((s.xp) == (2))
        #expect((s.tokenCarry) == (2_500))
        // 2 500 more reaches one XP exactly via the carry
        #expect((PetCare.feedTokens(2_500, state: &s, now: now, calendar: calendar)) == (1))
        #expect((s.tokenCarry) == (0))
        #expect((s.totalTokens) == (15_000))
        #expect((s.tokensToday) == (15_000))
    }

    @Test func testNoDailyCapAllTokensCountTowardXP() {
        var s = PetCareState()
        let now = date("2026-06-12 10:00")
        // 5M tokens in one day all convert to XP (1 per 5k).
        #expect((PetCare.feedTokens(5_000_000, state: &s, now: now, calendar: calendar)) == (1_000))
        #expect((s.tokensToday) == (5_000_000))
        #expect((s.totalTokens) == (5_000_000))
        // Next day the daily counter resets, lifetime keeps going.
        let tomorrow = date("2026-06-13 09:00")
        #expect((PetCare.feedTokens(5_000, state: &s, now: tomorrow, calendar: calendar)) == (1))
        #expect((s.tokensToday) == (5_000))
        #expect((s.totalTokens) == (5_005_000))
    }

    @Test func testTokensToNextLevel() {
        var s = PetCareState()
        // Fresh pet: level 2 needs 120 XP = 600k tokens.
        #expect((PetCare.tokensToNextLevel(state: s)) == (120 * 5_000))
        PetCare.feedTokens(12_500, state: &s, now: date("2026-06-12 10:00"), calendar: calendar)
        // 2 XP gained + 2 500 carry → (118 XP × 5k) − 2 500 left.
        #expect((PetCare.tokensToNextLevel(state: s)) == (118 * 5_000 - 2_500))
    }

    @Test func testMealGrantsFixedXP() {
        var s = PetCareState()
        let now = date("2026-06-12 10:00")
        #expect((PetCare.recordMeal(state: &s, now: now, calendar: calendar)) == (PetCare.mealXP))
        #expect((s.totalMeals) == (1))
        #expect((s.mealsToday) == (1))
        #expect((s.lastFedAt) == (now))
    }

    // MARK: - Hunger

    @Test func testHungerThresholds() {
        var s = PetCareState()
        let fed = date("2026-06-12 00:00")
        #expect((PetCare.hunger(state: s, now: fed)) == (.peckish), Comment(rawValue: "never fed → peckish"))
        PetCare.recordMeal(state: &s, now: fed, calendar: calendar)
        #expect((PetCare.hunger(state: s, now: date("2026-06-12 02:00"))) == (.full))
        #expect((PetCare.hunger(state: s, now: date("2026-06-12 06:00"))) == (.satisfied))
        #expect((PetCare.hunger(state: s, now: date("2026-06-12 12:00"))) == (.peckish))
        #expect((PetCare.hunger(state: s, now: date("2026-06-13 06:00"))) == (.hungry))
        #expect((PetCare.hunger(state: s, now: date("2026-06-14 06:00"))) == (.starving))
    }

    // MARK: - Streaks

    @Test func testStreakCountsConsecutiveDays() {
        var s = PetCareState()
        PetCare.recordMeal(state: &s, now: date("2026-06-12 10:00"), calendar: calendar)
        #expect((s.streakDays) == (1))
        // Same day: unchanged.
        PetCare.recordMeal(state: &s, now: date("2026-06-12 18:00"), calendar: calendar)
        #expect((s.streakDays) == (1))
        // Next day: +1.
        PetCare.recordMeal(state: &s, now: date("2026-06-13 09:00"), calendar: calendar)
        #expect((s.streakDays) == (2))
        // Skipping a day resets to 1.
        PetCare.recordMeal(state: &s, now: date("2026-06-15 09:00"), calendar: calendar)
        #expect((s.streakDays) == (1))
    }

    @Test func testDayRolloverResetsDailyCounters() {
        var s = PetCareState()
        PetCare.feedTokens(10_000, state: &s, now: date("2026-06-12 10:00"), calendar: calendar)
        PetCare.recordMeal(state: &s, now: date("2026-06-12 10:01"), calendar: calendar)
        PetCare.rollover(&s, now: date("2026-06-13 00:01"), calendar: calendar)
        #expect((s.tokensToday) == (0))
        #expect((s.mealsToday) == (0))
        #expect((s.totalTokens) == (10_000), Comment(rawValue: "lifetime totals survive the rollover"))
        #expect((s.totalMeals) == (1))
    }

    @Test func testDailyHistoryTracksFullBurnAndPrunes() {
        var s = PetCareState()
        PetCare.feedTokens(2_500_000, state: &s,
                           now: date("2026-06-12 10:00"), calendar: calendar)
        #expect((s.days?["2026-06-12"]) == (2_500_000), Comment(rawValue: "history keeps the full burn"))
        // 15 more days of feeding → history pruned to 14 entries.
        for day in 13...27 {
            PetCare.feedTokens(1_000, state: &s,
                               now: date(String(format: "2026-06-%02d 10:00", day)), calendar: calendar)
        }
        #expect((s.days?.count) == (14))
        #expect((s.days?["2026-06-12"]) == nil, Comment(rawValue: "oldest day dropped"))
        let recent = PetCare.recentDays(state: s, now: date("2026-06-27 12:00"), calendar: calendar)
        #expect((recent.count) == (7))
        #expect((recent.last?.tokens) == (1_000))
        #expect((recent.last?.label) == ("27"))
    }

    @Test func testOldStateWithoutDaysStillDecodes() throws {
        let old = #"{"xp":100,"tokenCarry":0,"tokensToday":50000,"mealsToday":0,"totalTokens":100,"totalMeals":1,"dayKey":"2026-06-12","streakDays":1}"#
        var s = try JSONDecoder().decode(PetCareState.self, from: old.data(using: .utf8)!)
        #expect((s.days) == nil)
        #expect((s.xp) == (100))
        // First feed after migrating seeds today's history from the running counter.
        PetCare.feedTokens(10_000, state: &s, now: date("2026-06-12 12:00"), calendar: calendar)
        #expect((s.days?["2026-06-12"]) == (60_000))
    }

    @Test func testStatePersistsThroughCodable() throws {
        var s = PetCareState()
        PetCare.feedTokens(123_456, state: &s, now: date("2026-06-12 10:00"), calendar: calendar)
        PetCare.recordMeal(state: &s, now: date("2026-06-12 11:00"), calendar: calendar)
        let data = try JSONEncoder().encode(s)
        let back = try JSONDecoder().decode(PetCareState.self, from: data)
        #expect((back) == (s))
    }
}
