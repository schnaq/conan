import XCTest
@testable import ConanCore
@testable import ConanMacropad

/// Watson with a fixed log (for recent project+tag combos) and fixed 28-day totals.
private final class PadMockWatson: WatsonClient, @unchecked Sendable {
    private let lock = NSLock()
    private var state: WatsonRunningFrame?

    func version() throws -> String { "mock" }
    func projects() throws -> [String] { ["kunde-a", "schnaq", "sales"] }
    func recentLog() throws -> [WatsonLogFrame] {
        [
            WatsonLogFrame(project: "kunde-a", tags: ["dev"], start: "2023-11-14T10:00:00+00:00"),
            WatsonLogFrame(project: "kunde-a", tags: ["review"], start: "2023-11-14T09:00:00+00:00"),
            WatsonLogFrame(project: "schnaq", tags: ["intern"], start: "2023-11-14T08:00:00+00:00"),
        ]
    }
    func projectTotals(since: Date) throws -> [String: TimeInterval] { ["kunde-a": 100, "schnaq": 50, "sales": 10] }
    func reportDay() throws -> WatsonReport {
        WatsonReport(projects: [.init(name: "kunde-a", tags: [], time: 3600)], time: 3600, timespan: .init(from: "", to: ""))
    }
    func reportWeek(containing reference: Date) throws -> WatsonReport {
        WatsonReport(projects: [], time: 0, timespan: .init(from: "", to: ""))
    }
    func add(_ command: WatsonAddCommand) throws {}
    func runningFrame() throws -> WatsonRunningFrame? { lock.lock(); defer { lock.unlock() }; return state }
    func setRunningFrame(_ frame: WatsonRunningFrame) throws { lock.lock(); state = frame; lock.unlock() }
    func clearRunningFrame() throws { lock.lock(); state = nil; lock.unlock() }
    func stopTime(project: String, startEpoch: Int) throws -> Date? { nil }
}

@MainActor
final class PadControllerTests: XCTestCase {
    private let base = Date(timeIntervalSince1970: 1_700_000_000)
    private var now = Date(timeIntervalSince1970: 1_700_000_000)
    private var idle: TimeInterval = 0
    private var stateURL: URL!
    private var defaults: UserDefaults!
    private var suite: String!
    private var store: SessionStore!
    private var pad: PadController!

    override func setUpWithError() throws {
        now = base
        idle = 0
        stateURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("conan-pad-\(UUID().uuidString)/state.json")
        suite = "conan-pad-tests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
        store = SessionStore(watson: PadMockWatson(), stateURL: stateURL, clock: { [unowned self] in self.now })
        store.refreshProjects()
        store.refreshReport()
        let deadline = Date().addingTimeInterval(2)
        while (store.recentTotals.isEmpty || store.recentCombos.isEmpty || store.todayReport == nil) && Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.01))
        }
        pad = PadController(store: store, defaults: defaults, clock: { [unowned self] in self.now }, idleSeconds: { [unowned self] in self.idle })
        _ = pad.state() // assigns the key slots: kunde-a, schnaq, sales
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(at: stateURL.deletingLastPathComponent())
    }

    func testSlotsFollowRankingAndPersist() {
        XCTAssertEqual(pad.slots, ["kunde-a", "schnaq", "sales", nil, nil, nil, nil, nil, nil])
        XCTAssertEqual(defaults.stringArray(forKey: PadController.slotsKey)?.prefix(3), ["kunde-a", "schnaq", "sales"])
    }

    func testKeyStartsProjectWithLastTags() {
        pad.handle(.key(0))
        XCTAssertEqual(store.main?.project, "kunde-a")
        XCTAssertEqual(store.main?.tags, ["dev"])
    }

    func testEmptyKeyDoesNothing() {
        pad.handle(.key(5))
        XCTAssertNil(store.main)
    }

    func testNebenPlusKeyTogglesSideAtHalf() {
        pad.handle(.key(0))
        pad.handle(.neben(down: true))
        pad.handle(.key(1))
        XCTAssertEqual(store.sideProjects.map(\.name), ["schnaq"])
        XCTAssertEqual(store.sideProjects.first?.percent, 0.5)
        XCTAssertEqual(store.sideProjects.first?.tags, ["intern"])
        pad.handle(.key(1))
        XCTAssertTrue(store.sideProjects.isEmpty)
    }

    func testKeyOfRunningSidePromotesItWithoutRunningTwice() {
        pad.handle(.key(0))
        pad.handle(.neben(down: true))
        pad.handle(.key(1))
        pad.handle(.neben(down: false))
        pad.handle(.key(1))
        XCTAssertEqual(store.main?.project, "schnaq")
        XCTAssertTrue(store.sideProjects.isEmpty)
    }

    func testNebenPlusKeyWithoutMainShowsNote() {
        pad.handle(.neben(down: true))
        pad.handle(.key(1))
        XCTAssertNil(store.main)
        pad.handle(.neben(down: false))
        XCTAssertEqual(pad.state().note, "erst Hauptprojekt")
        now = base.addingTimeInterval(2)
        XCTAssertNotEqual(pad.state().note, "erst Hauptprojekt")
    }

    func testNebenPlusMainKeyIsIgnored() {
        pad.handle(.key(0))
        pad.handle(.neben(down: true))
        pad.handle(.key(0))
        XCTAssertEqual(store.main?.project, "kunde-a")
        XCTAssertTrue(store.sideProjects.isEmpty)
    }

    func testPressingTheRunningMainKeyAgainDoesNotStopIt() {
        pad.handle(.key(0))
        now = base.addingTimeInterval(60)
        pad.handle(.key(0))
        XCTAssertEqual(store.main?.start, base)
    }

    func testEncoderPressStartsComboWhenIdle() {
        pad.handle(.encoder(1))
        let state = pad.state()
        XCTAssertEqual(state.view, "list")
        XCTAssertEqual(state.list, ["kunde-a +dev", "kunde-a +review", "schnaq +intern"])
        XCTAssertEqual(state.sel, 1)
        pad.handle(.press)
        XCTAssertEqual(store.main?.project, "kunde-a")
        XCTAssertEqual(store.main?.tags, ["review"])
        XCTAssertEqual(pad.state().view, "main")
    }

    func testEncoderPressRetagsRunningProject() {
        pad.handle(.key(0))
        pad.handle(.encoder(5)) // clamps to the last of kunde-a's two combos
        XCTAssertEqual(pad.state().list, ["kunde-a +dev", "kunde-a +review"])
        pad.handle(.press)
        XCTAssertEqual(store.main?.tags, ["review"])
        XCTAssertEqual(store.main?.start, base)
    }

    func testListStaysOpenLongEnoughToRead() {
        pad.handle(.encoder(1))
        now = base.addingTimeInterval(19)
        XCTAssertEqual(pad.state().view, "list")
        now = base.addingTimeInterval(20)
        XCTAssertEqual(pad.state().view, "main")
    }

    func testStopClosesAnOpenListWithoutStoppingTheTimer() {
        pad.handle(.key(0))
        pad.handle(.encoder(1))
        pad.handle(.stop)
        XCTAssertEqual(store.main?.project, "kunde-a")
        XCTAssertEqual(pad.state().view, "main")
        pad.handle(.stop) // list closed: STOP stops everything again
        XCTAssertNil(store.main)
    }

    func testTodayShowsGridWhileHeldAndFiveSecondsAfterShortPress() {
        pad.handle(.today(down: true))
        var state = pad.state()
        XCTAssertEqual(state.view, "grid")
        XCTAssertEqual(state.grid[0], ["kunde-a", "01:00"])
        XCTAssertEqual(state.grid[1], ["schnaq", "00:00"])
        XCTAssertNil(state.grid[3])
        pad.handle(.today(down: false))
        now = base.addingTimeInterval(4)
        XCTAssertEqual(pad.state().view, "grid")
        now = base.addingTimeInterval(5)
        state = pad.state()
        XCTAssertEqual(state.view, "main")
    }

    func testHoldingNebenShowsGridWithoutTimes() {
        pad.handle(.neben(down: true))
        let state = pad.state()
        XCTAssertEqual(state.view, "grid")
        XCTAssertEqual(state.grid[0], ["kunde-a", ""])
    }

    func testLedsForMainAndSide() {
        pad.handle(.key(0))
        pad.handle(.neben(down: true))
        pad.handle(.key(1))
        pad.handle(.neben(down: false))
        now = base.addingTimeInterval(10)
        let state = pad.state()
        XCTAssertEqual(state.leds[0], "101010")
        XCTAssertEqual(state.leds[3], "00ff00")
        XCTAssertEqual(state.leds[4], "ff8800")
        XCTAssertEqual(state.leds[5], "000000")
        XCTAssertEqual(state.note, "+1 neben")
        XCTAssertEqual(state.fx, "none")
    }

    func testRunningView() {
        pad.handle(.key(0))
        XCTAssertEqual(pad.state().fx, "blink")
        now = base.addingTimeInterval(3725)
        let state = pad.state()
        XCTAssertEqual(state.mood, "work")
        XCTAssertEqual(state.title, "kunde-a")
        XCTAssertEqual(state.sub, "+dev")
        XCTAssertEqual(state.time, "1:02:05")
    }

    func testIdleEscalationLightsProjectKeys() {
        _ = pad.state()
        now = base.addingTimeInterval(300)
        var state = pad.state()
        XCTAssertEqual(state.mood, "demand")
        XCTAssertEqual(state.leds[3], "ff8800")
        XCTAssertEqual(state.leds[6], "000000") // empty key stays dark
        XCTAssertEqual(state.fx, "pulse")
        now = base.addingTimeInterval(600)
        state = pad.state()
        XCTAssertEqual(state.mood, "alert")
        XCTAssertEqual(state.leds[3], "ff0000")
    }

    func testSleepNoteWhileTimerRuns() {
        pad.handle(.key(0))
        now = base.addingTimeInterval(3600)
        idle = 200
        let state = pad.state()
        XCTAssertEqual(state.mood, "sleep")
        XCTAssertEqual(state.note, "läuft noch 01:00")
        XCTAssertEqual(state.leds, Array(repeating: "000000", count: 12))
    }

    func testStopStopsEverything() {
        pad.handle(.key(0))
        pad.handle(.stop)
        XCTAssertNil(store.main)
    }
}
