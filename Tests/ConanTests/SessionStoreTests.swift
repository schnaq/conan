import XCTest
@testable import ConanCore

/// In-memory `WatsonClient` that simulates watson's `state` file (the running
/// frame) and captures the completed frames Conan writes via `add`.
private final class MockWatson: WatsonClient, @unchecked Sendable {
    private let lock = NSLock()
    private var _state: WatsonRunningFrame?
    private var _adds: [WatsonAddCommand] = []
    /// Stub for `stopTime`; when nil, callers fall back to their default stop.
    var stubStopTime: Date?

    init(state: WatsonRunningFrame? = nil) { _state = state }

    /// Simulate a terminal-side change to watson's state file
    /// (`watson start` sets a frame, `watson stop` clears it to nil).
    func setExternal(_ frame: WatsonRunningFrame?) {
        lock.lock(); _state = frame; lock.unlock()
    }

    var adds: [WatsonAddCommand] { lock.lock(); defer { lock.unlock() }; return _adds }

    // MARK: WatsonClient
    func version() throws -> String { "mock" }
    func projects() throws -> [String] { [] }
    func recentLog() throws -> [WatsonLogFrame] { [] }
    func reportDay() throws -> WatsonReport {
        WatsonReport(projects: [], time: 0, timespan: .init(from: "", to: ""))
    }

    func add(_ command: WatsonAddCommand) throws {
        lock.lock(); _adds.append(command); lock.unlock()
    }

    func runningFrame() throws -> WatsonRunningFrame? {
        lock.lock(); defer { lock.unlock() }; return _state
    }

    func setRunningFrame(_ frame: WatsonRunningFrame) throws {
        lock.lock(); _state = frame; lock.unlock()
    }

    func clearRunningFrame() throws {
        lock.lock(); _state = nil; lock.unlock()
    }

    func stopTime(project: String, startEpoch: Int) throws -> Date? { stubStopTime }
}

/// Mutable clock the tests advance by hand.
private final class TestClock: @unchecked Sendable {
    var now: Date
    init(_ now: Date) { self.now = now }
}

@MainActor
final class SessionStoreTests: XCTestCase {
    // 1_700_000_000 is an exact integer second, so epoch round-trips are lossless.
    private let base = Date(timeIntervalSince1970: 1_700_000_000)
    private var tempStateURL: URL!

    override func setUpWithError() throws {
        tempStateURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("conan-store-\(UUID().uuidString)/state.json")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempStateURL.deletingLastPathComponent())
    }

    private func makeStore(watson: MockWatson, clock: TestClock) -> SessionStore {
        SessionStore(watson: watson, stateURL: tempStateURL, clock: { clock.now })
    }

    /// Spin the main runloop until `condition` holds (lets detached `add` writes land).
    private func wait(until condition: @escaping () -> Bool, timeout: TimeInterval = 2, _ message: String = "") {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() && Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.01))
        }
        XCTAssertTrue(condition(), "condition not met within \(timeout)s \(message)")
    }

    /// Write a Conan `state.json` to disk to simulate a prior (crashed) session.
    private func persistPriorState(_ state: PersistedState) throws {
        try FileManager.default.createDirectory(
            at: tempStateURL.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        try encoder.encode(state).write(to: tempStateURL)
    }

    // MARK: - Steady-state reconcile

    func testAdoptsTerminalStart() {
        let watson = MockWatson()
        let clock = TestClock(base)
        let store = makeStore(watson: watson, clock: clock)

        // `watson start proj` in the terminal 100s ago.
        watson.setExternal(WatsonRunningFrame(project: "proj", start: base, tags: ["meeting"]))
        clock.now = base.addingTimeInterval(100)
        store.reconcile()

        XCTAssertEqual(store.main?.project, "proj")
        XCTAssertEqual(store.main?.start, base)
        XCTAssertEqual(store.main?.tags, ["meeting"])
        XCTAssertTrue(store.main?.wasAdopted ?? false)
        XCTAssertTrue(watson.adds.isEmpty, "adopting a still-open frame must not write any completed frame")
    }

    func testConanStartWritesRunningFrame() throws {
        let watson = MockWatson()
        let clock = TestClock(base)
        let store = makeStore(watson: watson, clock: clock)

        store.startMain(project: "x", tags: ["t"])

        let frame = try watson.runningFrame()
        XCTAssertEqual(frame?.project, "x")
        XCTAssertEqual(frame?.start, base)
        XCTAssertEqual(frame?.tags, ["t"])
    }

    func testInSyncReconcileIsNoop() {
        let watson = MockWatson()
        let clock = TestClock(base)
        let store = makeStore(watson: watson, clock: clock)
        store.startMain(project: "x")   // sets W = x

        store.reconcile()               // W matches main → nothing happens

        XCTAssertEqual(store.main?.project, "x")
        XCTAssertTrue(watson.adds.isEmpty)
    }

    func testTerminalStopFlushesSidesOnly() {
        let watson = MockWatson()
        let clock = TestClock(base)
        let store = makeStore(watson: watson, clock: clock)
        store.startMain(project: "x")                       // W = x, start base
        store.addSide(project: "y", percent: 0.5)          // side from base
        clock.now = base.addingTimeInterval(3600)

        // Terminal `watson stop`: watson wrote the main frame itself and cleared state.
        watson.setExternal(nil)
        store.reconcile()

        XCTAssertNil(store.main)
        wait(until: { watson.adds.count == 1 }, "expected exactly one (side) frame")
        // The main frame must NOT be written by Conan — watson already wrote it.
        XCTAssertFalse(watson.adds.contains { $0.project == "x" }, "double-count: Conan re-wrote the main frame")
        let side = watson.adds.first
        XCTAssertEqual(side?.project, "y")
        XCTAssertTrue(side?.tags.contains("conan") ?? false)
    }

    func testConanStopWritesMainAndSidesAndClearsRunningFrame() throws {
        let watson = MockWatson()
        let clock = TestClock(base)
        let store = makeStore(watson: watson, clock: clock)
        store.startMain(project: "x")
        store.addSide(project: "y", percent: 0.5)
        clock.now = base.addingTimeInterval(3600)

        store.stopAll()

        XCTAssertNil(store.main)
        XCTAssertNil(try watson.runningFrame(), "stopAll must drop the watson baton")
        wait(until: { watson.adds.count == 2 }, "expected main + side frames")
        XCTAssertTrue(watson.adds.contains { $0.project == "x" })
        XCTAssertTrue(watson.adds.contains { $0.project == "y" })
    }

    // MARK: - Crash recovery

    func testRecoveryTerminalStoppedWhileDeadFlushesSidesOnly() throws {
        // Prior session on disk; watson state now empty ⇒ `watson stop` ran while we were down.
        let prior = PersistedState(
            main: MainSession(project: "x", start: base),
            sideProjects: [SideProject(name: "y", percent: 0.5, intervalStart: base)],
            lastSeen: base.addingTimeInterval(3600)
        )
        try persistPriorState(prior)

        let watson = MockWatson(state: nil)
        let store = makeStore(watson: watson, clock: TestClock(base.addingTimeInterval(7200)))

        wait(until: { watson.adds.count == 1 }, "expected exactly one (side) frame")
        XCTAssertNil(store.main)
        XCTAssertFalse(watson.adds.contains { $0.project == "x" }, "double-count: main written by both watson and Conan")
        XCTAssertEqual(watson.adds.first?.project, "y")
    }

    func testRecoveryCrashMidSessionFlushesMainAndSides() throws {
        let prior = PersistedState(
            main: MainSession(project: "x", start: base),
            sideProjects: [SideProject(name: "y", percent: 0.5, intervalStart: base)],
            lastSeen: base.addingTimeInterval(3600)
        )
        try persistPriorState(prior)

        // watson state still holds the same frame ⇒ Conan crashed mid-session.
        let watson = MockWatson(state: WatsonRunningFrame(project: "x", start: base, tags: []))
        let store = makeStore(watson: watson, clock: TestClock(base.addingTimeInterval(7200)))

        wait(until: { watson.adds.count == 2 }, "expected main + side frames")
        XCTAssertNil(store.main)
        XCTAssertNil(try watson.runningFrame(), "recovery must drop the watson baton")
        XCTAssertTrue(watson.adds.contains { $0.project == "x" })
        XCTAssertTrue(watson.adds.contains { $0.project == "y" })
    }

    func testRecoveryAdoptsTerminalStartWhenNoPriorSession() throws {
        // No prior Conan state; a frame was started in the terminal while Conan was down.
        let watson = MockWatson(state: WatsonRunningFrame(project: "z", start: base, tags: ["deep"]))
        let store = makeStore(watson: watson, clock: TestClock(base.addingTimeInterval(60)))

        XCTAssertEqual(store.main?.project, "z")
        XCTAssertEqual(store.main?.tags, ["deep"])
        XCTAssertTrue(store.main?.wasAdopted ?? false)
        XCTAssertTrue(watson.adds.isEmpty)
    }
}
