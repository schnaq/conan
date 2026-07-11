import XCTest
@testable import ConanCore

/// Records `reportWeek` calls and returns a canned report; every other
/// operation is an inert stub.
private final class MockWatsonClient: WatsonClient, @unchecked Sendable {
    private let lock = NSLock()
    private var recordedReferences: [Date] = []
    let cannedWeekReport: WatsonReport

    init(cannedWeekReport: WatsonReport) {
        self.cannedWeekReport = cannedWeekReport
    }

    var weekReferences: [Date] {
        lock.lock(); defer { lock.unlock() }
        return recordedReferences
    }

    func version() throws -> String { "mock" }
    func projects() throws -> [String] { [] }
    func add(_ command: WatsonAddCommand) throws {}
    func recentLog() throws -> [WatsonLogFrame] { [] }
    func runningFrame() throws -> WatsonRunningFrame? { nil }
    func setRunningFrame(_ frame: WatsonRunningFrame) throws {}
    func clearRunningFrame() throws {}
    func stopTime(project: String, startEpoch: Int) throws -> Date? { nil }

    func reportDay() throws -> WatsonReport {
        WatsonReport(projects: [], time: 0, timespan: .init(from: "", to: ""))
    }

    func reportWeek(containing reference: Date) throws -> WatsonReport {
        lock.lock(); defer { lock.unlock() }
        recordedReferences.append(reference)
        return cannedWeekReport
    }
}

@MainActor
final class SessionStoreWeekTests: XCTestCase {
    private var tempDir: URL!
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private let cannedReport = WatsonReport(
        projects: [.init(name: "alpha", tags: [], time: 1234)],
        time: 1234,
        timespan: .init(from: "2023-11-13T00:00:00Z", to: "2023-11-20T00:00:00Z")
    )

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("conan-store-week-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    private func makeStore(mock: MockWatsonClient) -> SessionStore {
        SessionStore(
            watson: mock,
            stateURL: tempDir.appendingPathComponent("state.json"),
            clock: { self.now }
        )
    }

    private func waitUntil(
        _ condition: () -> Bool,
        file: StaticString = #filePath, line: UInt = #line
    ) async throws {
        for _ in 0..<200 {
            if condition() { return }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTFail("timed out waiting for condition", file: file, line: line)
    }

    func testShiftWeekClampsAtCurrentWeek() {
        let store = makeStore(mock: MockWatsonClient(cannedWeekReport: cannedReport))

        store.shiftWeek(by: 1)
        XCTAssertEqual(store.weekOffset, 0)

        store.shiftWeek(by: -1)
        XCTAssertEqual(store.weekOffset, -1)

        store.shiftWeek(by: 1)
        XCTAssertEqual(store.weekOffset, 0)
    }

    func testRefreshWeekReportPublishesReport() async throws {
        let store = makeStore(mock: MockWatsonClient(cannedWeekReport: cannedReport))

        store.refreshWeekReport()
        try await waitUntil { store.weekReport != nil }

        XCTAssertEqual(store.weekReport?.time, 1234)
        XCTAssertEqual(store.weekReport?.projects.first?.name, "alpha")
    }

    func testRefreshWeekReportPassesOffsetReference() async throws {
        let mock = MockWatsonClient(cannedWeekReport: cannedReport)
        let store = makeStore(mock: mock)

        store.shiftWeek(by: -1)
        try await waitUntil { store.weekReport != nil }

        XCTAssertEqual(mock.weekReferences.last, now.addingTimeInterval(-7 * 86_400))
    }
}
