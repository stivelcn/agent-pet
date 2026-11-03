import Testing
import Foundation
@testable import AgentPetCore

@Suite(.serialized)
final class AchievementTests {

    // MARK: - Shared helpers (mirror PetCareTests pattern)

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

    // MARK: - 1. First meal

    @Test func testFirstMealUnlocksOnFirstFeeding() {
        var state = PetCareState()
        let now = date("2026-06-18 10:00")
        PetCare.recordMeal(state: &state, now: now, calendar: calendar)

        let newly = PetCare.unlockNewAchievements(state: &state, now: now, calendar: calendar)

        #expect(newly.contains(.firstMeal), Comment(rawValue: "first meal should unlock .firstMeal; got \(newly)"))
    }

    // MARK: - 2. Level milestones

    @Test func testLevelMilestones() {
        var state = PetCareState()
        let now = date("2026-06-18 10:00")
        // XP to reach internal level 6 (display level 5) = xpToReach(6) = 60*6*5 = 1800
        // Feed enough meals to exceed that XP threshold.
        let targetXP = PetCare.xpToReach(level: 6)   // 1800
        let mealsNeeded = Int(ceil(Double(targetXP) / Double(PetCare.mealXP)))
        for _ in 0..<mealsNeeded {
            PetCare.recordMeal(state: &state, now: now, calendar: calendar)
        }

        let newly = PetCare.unlockNewAchievements(state: &state, now: now, calendar: calendar)

        #expect(newly.contains(.level5), Comment(rawValue: "display level ≥ 5 should unlock .level5; got \(newly)"))
    }

    // MARK: - 3. Token milestones

    @Test func testTokenMilestones() {
        var state = PetCareState()
        let now = date("2026-06-18 10:00")
        // Feed 1M tokens total
        PetCare.feedTokens(1_000_000, state: &state, now: now, calendar: calendar)

        let newly = PetCare.unlockNewAchievements(state: &state, now: now, calendar: calendar)

        #expect(newly.contains(.tokens1M), Comment(rawValue: "1M total tokens should unlock .tokens1M; got \(newly)"))
    }

    // MARK: - 4. Streak milestones

    @Test func testStreakMilestones() {
        var state = PetCareState()
        // Simulate 7 consecutive days of feeding
        for day in 1...7 {
            let d = date(String(format: "2026-06-%02d 10:00", day))
            PetCare.recordMeal(state: &state, now: d, calendar: calendar)
        }
        let lastDay = date("2026-06-07 10:00")

        let newly = PetCare.unlockNewAchievements(state: &state, now: lastDay, calendar: calendar)

        #expect(newly.contains(.streak7), Comment(rawValue: "7-day streak should unlock .streak7; got \(newly)"))
    }

    // MARK: - 5. Night owl

    @Test func testNightOwl() {
        var state = PetCareState()
        // Feed at 2am UTC
        let nightTime = date("2026-06-18 02:00")
        PetCare.recordMeal(state: &state, now: nightTime, calendar: calendar)

        let newly = PetCare.unlockNewAchievements(state: &state, now: nightTime, calendar: calendar)

        #expect(newly.contains(.nightOwl), Comment(rawValue: "feeding at 2am should unlock .nightOwl; got \(newly)"))
    }

    // MARK: - 6. No double unlock

    @Test func testNoDoubleUnlock() {
        var state = PetCareState()
        let now = date("2026-06-18 10:00")
        PetCare.recordMeal(state: &state, now: now, calendar: calendar)

        // First call — should contain firstMeal
        let first = PetCare.unlockNewAchievements(state: &state, now: now, calendar: calendar)
        #expect(first.contains(.firstMeal))

        // Second call with same state — firstMeal is already stored, must not appear again
        let second = PetCare.unlockNewAchievements(state: &state, now: now, calendar: calendar)
        #expect(!(second.contains(.firstMeal)), Comment(rawValue: "already-unlocked achievements must not be returned a second time"))
    }

    // MARK: - 7. Backward compat

    @Test func testBackwardCompat() throws {
        // JSON produced before unlockedAchievements field was added
        let legacy = """
        {"xp":200,"tokenCarry":0,"tokensToday":0,"mealsToday":0,\
        "totalTokens":200000,"totalMeals":5,"dayKey":"2026-06-18",\
        "streakDays":3}
        """
        let state = try JSONDecoder().decode(
            PetCareState.self,
            from: legacy.data(using: .utf8)!
        )
        #expect((state.unlockedAchievements) == nil, Comment(rawValue: "legacy JSON without achievements field must decode to nil"))
        #expect((state.xp) == (200))
    }

    // MARK: - 8. checkAchievements is pure

    @Test func testCheckAchievementsIsPure() {
        var state = PetCareState()
        let now = date("2026-06-18 10:00")
        PetCare.feedTokens(1_000_000, state: &state, now: now, calendar: calendar)

        let resultA = PetCare.checkAchievements(state: state, hour: 10)
        let resultB = PetCare.checkAchievements(state: state, hour: 10)

        #expect((resultA) == (resultB), Comment(rawValue: "checkAchievements must return identical sets for identical inputs"))
        // State must not have been mutated
        #expect((state.unlockedAchievements) == nil, Comment(rawValue: "checkAchievements must not mutate state"))
    }
}
