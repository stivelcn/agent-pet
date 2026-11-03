import Testing
import Foundation
@testable import AgentPetCore

@Suite(.serialized)
final class PetWindowPlannerTests {
    private func s(_ id: String, _ state: AgentState, project: String?) -> AgentSession {
        AgentSession(id: id, agentKind: .claude, project: project, state: state,
                     source: .hook, updatedAt: Date(timeIntervalSince1970: 0))
    }
    private let cat = ProjectPetMapping(projectPath: "/work/foo", petID: "cat")
    private func byKey(_ specs: [PetWindowSpec]) -> [String: PetWindowSpec] {
        Dictionary(uniqueKeysWithValues: specs.map { ($0.key, $0) })
    }

    // MARK: - Split OFF (single shared pet)

    @Test func testSplitOffSingleAggregateSpec() {
        let specs = PetWindowPlanner.plan(
            sessions: [s("1", .working, project: "/work/foo"), s("2", .waiting, project: "/x")],
            split: false, mappings: [cat], defaultPetID: "boba")
        #expect((specs.count) == (1))
        #expect((specs[0].key) == ("default"))
        #expect((specs[0].petID) == ("boba"))
        #expect((specs[0].mood) == (.working))      // working beats waiting
        #expect((specs[0].count) == (2))
    }

    @Test func testSplitOffIdleWhenNothingActive() {
        let specs = PetWindowPlanner.plan(sessions: [], split: false, mappings: [], defaultPetID: "boba")
        #expect((specs.map(\.key)) == (["default"]))
        #expect((specs[0].mood) == (.idle))
    }

    // MARK: - Split ON (only configured projects split off; the rest merge)

    @Test func testConfiguredProjectGetsOwnWindowRestMergeToDefault() {
        let specs = PetWindowPlanner.plan(
            sessions: [s("1", .working, project: "/work/foo/src"),   // matches cat
                       s("2", .done, project: "/other")],            // unconfigured → main pet
            split: true, mappings: [cat], defaultPetID: "boba")
        let m = byKey(specs)
        #expect((specs.count) == (2))                  // cat window + the main pet
        #expect((m["/work/foo"]?.petID) == ("cat"))
        #expect((m["/work/foo"]?.projectName) == ("foo"))
        #expect((m["/work/foo"]?.mood) == (.working))
        #expect((m["/other"]) == nil, Comment(rawValue: "an unconfigured project must not get its own window"))
        #expect((m["default"]?.petID) == ("boba"))     // /other folds into the main pet
        #expect((m["default"]?.mood) == (.done))
        #expect((m["default"]?.count) == (1))
    }

    @Test func testSubfolderSessionsCollapseToConfiguredRoot() {
        let specs = PetWindowPlanner.plan(
            sessions: [s("1", .working, project: "/work/foo/a"), s("2", .working, project: "/work/foo/b")],
            split: true, mappings: [cat], defaultPetID: "boba")
        let m = byKey(specs)
        #expect((m["/work/foo"]?.count) == (2))
        #expect((m["/work/foo"]?.mood) == (.working))
        #expect((m["default"]?.count) == (0))          // main pet always present, idle here
        #expect((m["default"]?.mood) == (.idle))
    }

    @Test func testConfiguredProjectPersistsWhenIdle() {
        // A configured project with no active session still shows its idle window
        // (does not vanish when its agent stops).
        let specs = PetWindowPlanner.plan(sessions: [], split: true, mappings: [cat], defaultPetID: "boba")
        let m = byKey(specs)
        #expect((m["/work/foo"]?.petID) == ("cat"))
        #expect((m["/work/foo"]?.mood) == (.idle))
        #expect((m["default"]?.mood) == (.idle))
    }

    @Test func testRemovingMappingFoldsBackToMainPet() {
        // Same session, but its mapping was removed → it merges into the main pet
        // and gets no window of its own.
        let specs = PetWindowPlanner.plan(
            sessions: [s("1", .working, project: "/work/foo")],
            split: true, mappings: [], defaultPetID: "boba")
        #expect((specs.map(\.key)) == (["default"]))
        #expect((specs[0].mood) == (.working))
        #expect((specs[0].count) == (1))
    }

    @Test func testProjectlessSessionsGoToMainPet() {
        let specs = PetWindowPlanner.plan(
            sessions: [s("1", .working, project: nil)],
            split: true, mappings: [cat], defaultPetID: "boba")
        let m = byKey(specs)
        #expect((m["default"]?.mood) == (.working))    // no project → main pet
        #expect((m["/work/foo"]?.mood) == (.idle))     // configured cat still shown, idle
    }

    @Test func testRegisteredAndIdleNotActive() {
        let specs = PetWindowPlanner.plan(
            sessions: [s("1", .idle, project: "/work/foo"), s("2", .registered, project: "/y")],
            split: true, mappings: [cat], defaultPetID: "boba")
        let m = byKey(specs)
        #expect((m["/work/foo"]?.mood) == (.idle))     // nothing active
        #expect((m["default"]?.mood) == (.idle))
        #expect((m["/y"]) == nil, Comment(rawValue: "non-active unconfigured project gets no window"))
    }

    @Test func testSplitAlwaysHasMainPetWindow() {
        // The "default" (main pet) window is always present in split mode, so the
        // break nudge and project-less work always have a pet to show.
        let specs = PetWindowPlanner.plan(
            sessions: [s("1", .working, project: "/work/foo")],
            split: true, mappings: [cat], defaultPetID: "boba")
        #expect(specs.contains { $0.key == "default" })
    }

    @Test func testHideIdleProjectsDropsIdleConfiguredWindow() {
        // Configured project idle + hideIdleProjects on → only the main pet shows.
        let idle = PetWindowPlanner.plan(
            sessions: [], split: true, mappings: [cat], defaultPetID: "boba", hideIdleProjects: true)
        #expect((idle.map(\.key)) == (["default"]))
        // When it's active again, its window comes back even with the option on.
        let active = PetWindowPlanner.plan(
            sessions: [s("1", .working, project: "/work/foo")],
            split: true, mappings: [cat], defaultPetID: "boba", hideIdleProjects: true)
        #expect(active.contains { $0.key == "/work/foo" })
    }

    @Test func testForceDefaultDoesNotDuplicateMainPet() {
        let specs = PetWindowPlanner.plan(
            sessions: [], split: true, mappings: [cat], defaultPetID: "boba", forceDefault: true)
        #expect((specs.filter { $0.key == "default" }.count) == (1))
    }

    // MARK: - windowKeys

    @Test func testWindowKeysSplitOffAlwaysReturnsDefault() {
        let keys = PetWindowPlanner.windowKeys(forPetID: "cat", split: false,
                                               mappings: [cat], selectedPetID: "cat")
        #expect((keys) == (["default"]))
    }

    @Test func testWindowKeysSplitOnMappedPet() {
        let keys = PetWindowPlanner.windowKeys(forPetID: "cat", split: true,
                                               mappings: [cat], selectedPetID: "boba")
        // cat mapped to /work/foo → normalized key
        #expect(keys.contains(where: { $0.contains("foo") }))
        #expect(!(keys.contains("default")))
    }

    @Test func testWindowKeysSplitOnSelectedPetIncludesDefault() {
        let keys = PetWindowPlanner.windowKeys(forPetID: "boba", split: true,
                                               mappings: [cat], selectedPetID: "boba")
        #expect(keys.contains("default"))
    }

    @Test func testWindowKeysSplitOnSharedPetMultipleKeys() {
        let m1 = ProjectPetMapping(projectPath: "/work/foo", petID: "cat")
        let m2 = ProjectPetMapping(projectPath: "/work/bar", petID: "cat")
        let keys = PetWindowPlanner.windowKeys(forPetID: "cat", split: true,
                                               mappings: [m1, m2], selectedPetID: "boba")
        #expect((keys.count) == (2))
        #expect(keys.contains(where: { $0.contains("foo") }))
        #expect(keys.contains(where: { $0.contains("bar") }))
    }

    @Test func testWindowKeysSplitOnUnknownPetFallsToDefault() {
        let keys = PetWindowPlanner.windowKeys(forPetID: "unknown", split: true,
                                               mappings: [cat], selectedPetID: "boba")
        #expect((keys) == (["default"]))
    }
}

@Suite(.serialized)
final class PetWindowGeometryTests {
    // 1920x1080 primary display, menu bar 25pt tall (visibleFrame excludes it).
    private let visible = CGRect(x: 0, y: 0, width: 1920, height: 1055)
    private let size = CGSize(width: 260, height: 320)

    @Test func testInsidePositionIsUnchanged() {
        let p = CGPoint(x: 800, y: 400)
        #expect((PetWindowGeometry.clampOrigin(p, size: size, into: visible)) == (p))
    }

    @Test func testOffRightEdgeClampsBackIn() {
        // The issue's repro: X=2181 on a 1920-wide screen -> pulled fully on-screen.
        let clamped = PetWindowGeometry.clampOrigin(CGPoint(x: 2181, y: 375), size: size, into: visible)
        #expect((clamped.x) == (CGFloat(1920 - 260)))   // maxX - width
        #expect((clamped.y) == (375))
        #expect((clamped.x + size.width) <= (visible.maxX))
    }

    @Test func testOffLeftAndBottomClampToMinEdges() {
        let clamped = PetWindowGeometry.clampOrigin(CGPoint(x: -500, y: -200), size: size, into: visible)
        #expect((clamped) == (CGPoint(x: 0, y: 0)))
    }

    @Test func testWindowLargerThanScreenPinsToMinEdge() {
        let big = CGSize(width: 3000, height: 320)
        let clamped = PetWindowGeometry.clampOrigin(CGPoint(x: 2181, y: 40), size: big, into: visible)
        #expect((clamped.x) == (0))   // wider than screen -> pin to minX, never negative
    }

    @Test func testOffscreenOriginOnShiftedScreenClamps() {
        // Secondary display whose frame starts at x=1920 (to the right).
        let right = CGRect(x: 1920, y: 0, width: 1920, height: 1055)
        let clamped = PetWindowGeometry.clampOrigin(CGPoint(x: 5000, y: 400), size: size, into: right)
        #expect((clamped.x) == (CGFloat(1920 + 1920 - 260)))
    }

    // MARK: clampOrigin's Y, as used after a drag (pet dropped past the bottom)

    @Test func testDroppedBelowBottomComesBackUp() {
        let pet = CGSize(width: 176, height: 170)
        // Window 61pt below the screen (the reported bug).
        #expect((PetWindowGeometry.clampOrigin(CGPoint(x: 700, y: -61), size: pet, into: visible).y) == (0))
        // A secondary display whose visible frame starts below zero.
        let right = CGRect(x: 1680, y: -102, width: 2048, height: 1152)
        #expect((PetWindowGeometry.clampOrigin(CGPoint(x: 2600, y: -490), size: pet, into: right).y) == (-102))
    }

    @Test func testWindowTallerThanScreenKeepsBottomVisible() {
        // A tall bubble: the bottom (where the pet is) wins over the top.
        let tall = CGSize(width: 176, height: 1200)
        #expect((PetWindowGeometry.clampOrigin(CGPoint(x: 700, y: 500), size: tall, into: visible).y) == (0))
    }

    // MARK: nearestRectIndex (pet dropped outside every screen)

    @Test func testNearestRectPicksContainingThenClosest() {
        let left = CGRect(x: 0, y: 0, width: 1680, height: 1020)
        let right = CGRect(x: 1680, y: -102, width: 2048, height: 1152)
        let screens = [left, right]
        #expect((PetWindowGeometry.nearestRectIndex(to: CGPoint(x: 800, y: 500), in: screens)) == (0))
        #expect((PetWindowGeometry.nearestRectIndex(to: CGPoint(x: 2600, y: 500), in: screens)) == (1))
        #expect((PetWindowGeometry.nearestRectIndex(to: CGPoint(x: 4100, y: 400), in: screens)) == (1))  // past right
        #expect((PetWindowGeometry.nearestRectIndex(to: CGPoint(x: -340, y: 500), in: screens)) == (0))  // past left
        #expect((PetWindowGeometry.nearestRectIndex(to: CGPoint(x: 850, y: 1300), in: screens)) == (0))  // above left
        #expect((PetWindowGeometry.nearestRectIndex(to: CGPoint(x: 2700, y: -500), in: screens)) == (1)) // below right
        #expect((PetWindowGeometry.nearestRectIndex(to: .zero, in: [])) == nil)
    }

    // MARK: horizontalLayout (bubble stays on the pet's screen, pet stays put)

    @Test func testLayoutCentredWhenRoomOnBothSides() {
        let r = PetWindowGeometry.horizontalLayout(anchorX: 800, width: 364, petWidth: 120,
                                                   visibleMinX: 0, visibleMaxX: 1680)
        #expect((r.originX) == (CGFloat(800 - 182)))
        #expect((r.petOffset) == (0))
    }

    @Test func testLayoutNearRightEdgeShiftsWindowButNotPet() {
        // Repro: pet at x=1558 on a 1680-wide display with a second display to the right.
        let r = PetWindowGeometry.horizontalLayout(anchorX: 1558, width: 364, petWidth: 120,
                                                   visibleMinX: 0, visibleMaxX: 1680)
        #expect((r.originX) == (CGFloat(1680 - 364)))                     // fully on this screen
        #expect((r.originX + 364 / 2 + r.petOffset) == (1558))   // pet unchanged
    }

    @Test func testLayoutNearLeftEdgeOnShiftedScreen() {
        // Pet fully on the right display (spans 1700...1820), bubble would spill left.
        let r = PetWindowGeometry.horizontalLayout(anchorX: 1760, width: 364, petWidth: 120,
                                                   visibleMinX: 1680, visibleMaxX: 3728)
        #expect((r.originX) == (1680))
        #expect((r.originX + 182 + r.petOffset) == (1760))
    }

    @Test func testLayoutPetPastEdgeIsPulledInsideWindow() {
        // Pet dragged half off the right edge: offset is limited to keep it in the window.
        let r = PetWindowGeometry.horizontalLayout(anchorX: 1670, width: 364, petWidth: 120,
                                                   visibleMinX: 0, visibleMaxX: 1680)
        #expect((r.originX) == (1316))
        #expect((r.petOffset) == (122))   // (364 - 120) / 2
    }

    @Test func testLayoutWindowWiderThanScreenPinsToMinX() {
        let r = PetWindowGeometry.horizontalLayout(anchorX: 100, width: 500, petWidth: 120,
                                                   visibleMinX: 0, visibleMaxX: 400)
        #expect((r.originX) == (0))
        #expect((r.petOffset) == (-150))
    }

    // MARK: bubbleLayout (bubble + tail follow the offset pet)

    private func bubble(offset: CGFloat, window: CGFloat, bubble: CGFloat) -> (bubbleShift: CGFloat, tailShift: CGFloat) {
        PetWindowGeometry.bubbleLayout(petOffset: offset, windowWidth: window, bubbleWidth: bubble,
                                       bubbleInset: 10, tailClearance: 20)
    }

    @Test func testSettledWideBubbleStaysPutAndTailPointsAtPet() {
        let r = bubble(offset: 60, window: 364, bubble: 364)
        #expect((r.bubbleShift) == (0))   // no room left in the window
        #expect((r.tailShift) == (60))
    }

    @Test func testNarrowBubbleMovesOverPet() {
        // Mid scale-in/out: plenty of room, the whole bubble sits over the pet.
        let r = bubble(offset: 60, window: 364, bubble: 120)
        #expect((r.bubbleShift) == (60))
        #expect((r.tailShift) == (0))
    }

    @Test func testShrinkingBubbleUsesOldWindowWidth() {
        // Bubble already narrow, window still wide: bubble can reach the pet.
        let r = bubble(offset: -100, window: 364, bubble: 150)
        #expect((r.bubbleShift) == (-100))
        #expect((r.tailShift) == (0))
    }

    @Test func testTailClearOfCorners() {
        // Tail limit = (100 - 2*10)/2 - 20 = 20.
        let r = bubble(offset: 50, window: 100, bubble: 100)
        #expect((r.bubbleShift) == (0))
        #expect((r.tailShift) == (20))
    }

    @Test func testNoOffsetIsNoShift() {
        let r = bubble(offset: 0, window: 364, bubble: 200)
        #expect((r.bubbleShift) == (0))
        #expect((r.tailShift) == (0))
    }
}
