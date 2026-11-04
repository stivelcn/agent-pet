import Foundation
import Testing
@testable import AgentPetCore

struct PetCareTrendTests {
    private func calendar(_ zone: String = "Asia/Shanghai") -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: zone)!
        return calendar
    }

    @Test func recentDaysKeepFullDatesAcrossMonthBoundaryAndExactTokens() {
        var state = PetCareState()
        state.days = ["2026-10-29": 125, "2026-11-03": 7_245_678, "2026-11-04": 54_321]
        let now = ISO8601DateFormatter().date(from: "2026-11-04T12:00:00+08:00")!
        let days = PetCare.recentDays(state: state, now: now, calendar: calendar())
        #expect(days.map(\.id) == ["2026-10-29", "2026-10-30", "2026-10-31", "2026-11-01", "2026-11-02", "2026-11-03", "2026-11-04"])
        #expect(days.map(\.label) == ["29", "30", "31", "1", "2", "3", "4"])
        #expect(days.map(\.tokens) == [125, 0, 0, 0, 0, 7_245_678, 54_321])
        #expect(Set(days.map(\.id)).count == 7)
    }

    @Test func emptyHistoryStillHasSevenHoverableZeroDays() {
        var state = PetCareState()
        state.days = nil
        let now = ISO8601DateFormatter().date(from: "2027-01-02T00:01:00+08:00")!
        let days = PetCare.recentDays(state: state, now: now, calendar: calendar())
        #expect(days.count == 7)
        #expect(days.first?.id == "2026-12-27")
        #expect(days.last?.id == "2027-01-02")
        #expect(days.allSatisfy { $0.tokens == 0 })
    }

    @Test func localDateAndDSTDoNotShiftOrDuplicateDays() {
        let now = ISO8601DateFormatter().date(from: "2026-11-02T07:30:00Z")!
        let days = PetCare.recentDays(state: PetCareState(), now: now, calendar: calendar("America/Los_Angeles"))
        #expect(days.map(\.id) == ["2026-10-26", "2026-10-27", "2026-10-28", "2026-10-29", "2026-10-30", "2026-10-31", "2026-11-01"])
    }

    @Test func nonpositiveDayCountsAreEmpty() {
        #expect(PetCare.recentDays(state: PetCareState(), now: Date(), count: 0).isEmpty)
        #expect(PetCare.recentDays(state: PetCareState(), now: Date(), count: -1).isEmpty)
    }
}
