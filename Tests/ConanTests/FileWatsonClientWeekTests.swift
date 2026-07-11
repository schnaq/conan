import XCTest
@testable import ConanCore

final class FileWatsonClientWeekTests: XCTestCase {
    private var tempDir: URL!
    private let utc = TimeZone(identifier: "UTC")!
    // 1_700_000_000 == Tue 2023-11-14 22:13:20 UTC.
    private let now = Date(timeIntervalSince1970: 1_700_000_000)
    // ISO week containing `now`: Mon 2023-11-13 00:00 → Mon 2023-11-20 00:00 UTC.
    private let weekStart = Date(timeIntervalSince1970: 1_699_833_600)
    private let weekEnd = Date(timeIntervalSince1970: 1_700_438_400)

    override func setUpWithError() throws {
        tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("conan-fwc-week-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    private func makeClient() -> FileWatsonClient {
        FileWatsonClient(dataDirectory: tempDir, timeZone: utc, now: { self.now })
    }

    private func writeRawFrames(_ frames: [[Any]]) throws {
        try JSONSerialization.data(withJSONObject: frames)
            .write(to: tempDir.appendingPathComponent("frames"))
    }

    /// Raw watson frame row offset relative to the week start.
    private func frame(_ project: String, startOffset: TimeInterval, duration: TimeInterval, tags: [String] = []) -> [Any] {
        let start = Int(weekStart.timeIntervalSince1970 + startOffset)
        return [start, start + Int(duration), project, "id-\(project)-\(Int(startOffset))", tags, start]
    }

    func testWeekSpansISOMondayToMonday() throws {
        let report = try makeClient().reportWeek(containing: now)

        XCTAssertEqual(report.timespan.from, "2023-11-13T00:00:00Z")
        XCTAssertEqual(report.timespan.to, "2023-11-20T00:00:00Z")
    }

    func testSundayReferenceBelongsToSameMondayWeek() throws {
        // Sun 2023-11-19: with Sunday-start weeks this would roll into the next
        // week; ISO (Monday-start) keeps it in the same one.
        let sunday = now.addingTimeInterval(5 * 86_400)

        let report = try makeClient().reportWeek(containing: sunday)

        XCTAssertEqual(report.timespan.from, "2023-11-13T00:00:00Z")
        XCTAssertEqual(report.timespan.to, "2023-11-20T00:00:00Z")
    }

    func testAggregatesAcrossDaysByProjectAndTag() throws {
        try writeRawFrames([
            frame("alpha", startOffset: 9 * 3600, duration: 3600, tags: ["meeting"]),                // Mon 1h
            frame("alpha", startOffset: 2 * 86_400 + 9 * 3600, duration: 7200, tags: ["dev"]),       // Wed 2h
            frame("beta", startOffset: 3 * 86_400 + 14 * 3600, duration: 1800),                      // Thu 30m
        ])

        let report = try makeClient().reportWeek(containing: now)

        XCTAssertEqual(report.time, 12_600)
        let alpha = report.projects.first { $0.name == "alpha" }
        XCTAssertEqual(alpha?.time, 10_800)
        XCTAssertEqual(alpha?.tags.first { $0.name == "meeting" }?.time, 3600)
        XCTAssertEqual(alpha?.tags.first { $0.name == "dev" }?.time, 7200)
        XCTAssertEqual(report.projects.first { $0.name == "beta" }?.time, 1800)
    }

    func testClipsFramesAtWeekBoundaries() throws {
        try writeRawFrames([
            frame("alpha", startOffset: -3600, duration: 7200),                 // Sun 23:00 → Mon 01:00: 1h in-week
            frame("alpha", startOffset: 7 * 86_400 - 1800, duration: 3600),     // Sun 23:30 → Mon 00:30: 30m in-week
        ])

        let report = try makeClient().reportWeek(containing: now)

        XCTAssertEqual(report.time, 5400)
        XCTAssertEqual(report.projects.first?.time, 5400)
    }

    func testEmptyWeekReturnsZeroReport() throws {
        try writeRawFrames([
            frame("alpha", startOffset: -3 * 86_400, duration: 3600),           // previous week only
        ])

        let report = try makeClient().reportWeek(containing: now)

        XCTAssertTrue(report.projects.isEmpty)
        XCTAssertEqual(report.time, 0)
        XCTAssertEqual(report.timespan.from, "2023-11-13T00:00:00Z")
    }
}
