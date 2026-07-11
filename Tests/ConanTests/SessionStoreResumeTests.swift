import XCTest
@testable import ConanCore

/// Minimal `WatsonClient` that only simulates watson's `state` file (the
/// running frame), so reconcile paths can be driven from tests.
private final class StateOnlyMockWatson: WatsonClient, @unchecked Sendable {
    private let lock = NSLock()
    private var state: WatsonRunningFrame?

    /// Simulate a terminal-side change (`watson start`/`watson stop`).
    func setExternal(_ frame: WatsonRunningFrame?) {
        lock.lock(); state = frame; lock.unlock()
    }

    func version() throws -> String { "mock" }
    func projects() throws -> [String] { [] }
    func add(_ command: WatsonAddCommand) throws {}
    func recentLog() throws -> [WatsonLogFrame] { [] }
    func reportDay() throws -> WatsonReport {
        WatsonReport(projects: [], time: 0, timespan: .init(from: "", to: ""))
    }

    func runningFrame() throws -> WatsonRunningFrame? {
        lock.lock(); defer { lock.unlock() }; return state
    }

    func setRunningFrame(_ frame: WatsonRunningFrame) throws {
        lock.lock(); state = frame; lock.unlock()
    }

    func clearRunningFrame() throws {
        lock.lock(); state = nil; lock.unlock()
    }

    func stopTime(project: String, startEpoch: Int) throws -> Date? { nil }
}

@MainActor
final class SessionStoreResumeTests: XCTestCase {
    private var tempDir: URL!
    private var stateURL: URL!
    private var now = Date(timeIntervalSince1970: 1_700_000_000)

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("conan-store-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        stateURL = tempDir.appendingPathComponent("state.json")
        now = Date(timeIntervalSince1970: 1_700_000_000)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    private func makeStore() -> SessionStore {
        SessionStore(watson: nil, stateURL: stateURL, clock: { self.now })
    }

    private func startTypicalSetup(_ store: SessionStore) {
        store.startMain(project: "acme", tags: ["dev"])
        store.addSide(project: "admin", percent: 0.1, tags: ["ops"])
        store.addSide(project: "mail", percent: 0.05)
    }

    private var typicalSetup: SessionSetup {
        SessionSetup(
            mainProject: "acme",
            mainTags: ["dev"],
            sides: [
                SessionSetup.Side(name: "admin", percent: 0.1, tags: ["ops"]),
                SessionSetup.Side(name: "mail", percent: 0.05, tags: []),
            ]
        )
    }

    func testStopAllCapturesLastSetup() {
        let store = makeStore()
        startTypicalSetup(store)
        now = now.addingTimeInterval(600)

        store.stopAll()

        XCTAssertNil(store.main)
        XCTAssertTrue(store.sideProjects.isEmpty)
        XCTAssertEqual(store.lastSetup, typicalSetup)
    }

    func testResumeAllRestartsSetupWithFreshTimestamps() {
        let store = makeStore()
        startTypicalSetup(store)
        now = now.addingTimeInterval(600)
        store.stopAll()
        let resumeTime = now.addingTimeInterval(1_800)
        now = resumeTime

        store.resumeAll()

        XCTAssertEqual(store.main?.project, "acme")
        XCTAssertEqual(store.main?.tags, ["dev"])
        XCTAssertEqual(store.main?.start, resumeTime)
        XCTAssertEqual(store.sideProjects.map(\.name), ["admin", "mail"])
        XCTAssertEqual(store.sideProjects.map(\.percent), [0.1, 0.05])
        XCTAssertEqual(store.sideProjects.map(\.tags), [["ops"], []])
        XCTAssertEqual(store.sideProjects.map(\.intervalStart), [resumeTime, resumeTime])
    }

    func testResumeAllNoOpWhenAlreadyRunning() {
        let store = makeStore()
        startTypicalSetup(store)
        store.stopAll()
        store.startMain(project: "other")

        store.resumeAll()

        XCTAssertEqual(store.main?.project, "other")
        XCTAssertTrue(store.sideProjects.isEmpty)
    }

    func testResumeAllNoOpWithoutSnapshot() {
        let store = makeStore()

        store.resumeAll()

        XCTAssertNil(store.main)
        XCTAssertNil(store.lastSetup)
    }

    func testLastSetupSurvivesRelaunch() {
        let store = makeStore()
        startTypicalSetup(store)
        now = now.addingTimeInterval(600)
        store.stopAll()

        let relaunched = makeStore()

        XCTAssertEqual(relaunched.lastSetup, typicalSetup)
    }

    func testOldStateFileWithoutLastSetupKeyDecodes() throws {
        let legacy = #"{"main": null, "sideProjects": [], "lastSeen": 1700000000}"#
        try legacy.data(using: .utf8)!.write(to: stateURL)

        let store = makeStore()

        XCTAssertNil(store.main)
        XCTAssertNil(store.lastSetup)
    }

    func testCrashRecoverySnapshotsInterruptedSetup() {
        let store = makeStore()
        startTypicalSetup(store)
        now = now.addingTimeInterval(600)
        // No stopAll: simulate quit/crash while tracking. state.json still holds
        // the open session from the last persist.

        let relaunched = makeStore()

        XCTAssertNil(relaunched.main)
        XCTAssertTrue(relaunched.sideProjects.isEmpty)
        XCTAssertEqual(relaunched.lastSetup, typicalSetup)
    }

    func testTerminalStopSnapshotsSetupForResume() {
        let watson = StateOnlyMockWatson()
        let store = SessionStore(watson: watson, stateURL: stateURL, clock: { self.now })
        store.startMain(project: "acme", tags: ["dev"])
        store.addSide(project: "admin", percent: 0.1, tags: ["ops"])
        now = now.addingTimeInterval(600)

        watson.setExternal(nil)   // terminal `watson stop`
        store.reconcile()

        XCTAssertNil(store.main)
        XCTAssertEqual(
            store.lastSetup,
            SessionSetup(
                mainProject: "acme",
                mainTags: ["dev"],
                sides: [SessionSetup.Side(name: "admin", percent: 0.1, tags: ["ops"])]
            )
        )
    }

    func testSetPercentBeforeStopAllSnapshotsCurrentPercent() {
        let store = makeStore()
        store.startMain(project: "acme")
        store.addSide(project: "admin", percent: 0.1)
        let sideID = store.sideProjects[0].id
        now = now.addingTimeInterval(300)
        store.setPercent(sideID, percent: 0.25)
        now = now.addingTimeInterval(300)

        store.stopAll()

        XCTAssertEqual(store.lastSetup?.sides.map(\.percent), [0.25])
    }
}
