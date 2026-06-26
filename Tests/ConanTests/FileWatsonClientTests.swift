import XCTest
@testable import ConanCore

final class FileWatsonClientTests: XCTestCase {
    private var tempDir: URL!
    private let utc = TimeZone(identifier: "UTC")!
    // 1_700_000_000 == 2023-11-14 22:13:20 UTC
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    override func setUpWithError() throws {
        tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("conan-fwc-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    private func makeClient() -> FileWatsonClient {
        FileWatsonClient(dataDirectory: tempDir, timeZone: utc, now: { self.now })
    }

    private var dayStart: Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = utc
        return calendar.startOfDay(for: now)
    }

    private func writeRawFrames(_ frames: [[Any]]) throws {
        try JSONSerialization.data(withJSONObject: frames)
            .write(to: tempDir.appendingPathComponent("frames"))
    }

    func testAddAndReportRoundTrip() throws {
        let client = makeClient()
        let start = dayStart.addingTimeInterval(9 * 3600)
        try client.add(Accrual.addCommand(project: "main", start: start, accruedSeconds: 3600, tags: [], timeZone: utc)!)
        try client.add(Accrual.addCommand(project: "side", start: start, accruedSeconds: 360, tags: ["conan"], timeZone: utc)!)

        let report = try client.reportDay()
        XCTAssertEqual(report.time, 3960)
        XCTAssertEqual(report.projects.first { $0.name == "main" }?.time, 3600)
        XCTAssertTrue(report.projects.first { $0.name == "main" }?.tags.isEmpty ?? false)
        let side = report.projects.first { $0.name == "side" }
        XCTAssertEqual(side?.time, 360)
        XCTAssertEqual(side?.tags.first?.name, "conan")
        XCTAssertEqual(side?.tags.first?.time, 360)
    }

    func testWritesWatsonFrameFormat() throws {
        let client = makeClient()
        let start = dayStart.addingTimeInterval(9 * 3600)
        try client.add(Accrual.addCommand(project: "p", start: start, accruedSeconds: 3600, tags: ["x"], timeZone: utc)!)

        let data = try Data(contentsOf: tempDir.appendingPathComponent("frames"))
        let rows = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [[Any]])
        XCTAssertEqual(rows.count, 1)
        let row = rows[0]
        XCTAssertEqual(row.count, 6)
        XCTAssertEqual(row[0] as? Int, Int(start.timeIntervalSince1970))           // start epoch
        XCTAssertEqual(row[1] as? Int, Int(start.timeIntervalSince1970) + 3600)    // stop epoch
        XCTAssertEqual(row[2] as? String, "p")
        XCTAssertEqual((row[3] as? String)?.count, 32)                             // uuid hex
        XCTAssertEqual(row[4] as? [String], ["x"])
        XCTAssertNotNil(row[5] as? Int)                                            // updated_at
    }

    func testReadsExistingWatsonFrames() throws {
        let start = Int(dayStart.timeIntervalSince1970)
        try writeRawFrames([[start + 8 * 3600, start + 9 * 3600, "alpha", "id1", ["meeting"], start]])

        let client = makeClient()
        XCTAssertEqual(try client.projects(), ["alpha"])
        let report = try client.reportDay()
        XCTAssertEqual(report.projects.first?.name, "alpha")
        XCTAssertEqual(report.projects.first?.time, 3600)
        XCTAssertEqual(report.projects.first?.tags.first?.name, "meeting")
    }

    func testReportClipsFrameToToday() throws {
        let start = Int(dayStart.timeIntervalSince1970)
        // Spans yesterday 23:00 → today 01:00 (2h total); only 1h is today.
        try writeRawFrames([[start - 3600, start + 3600, "span", "id1", [], start]])
        let report = try makeClient().reportDay()
        XCTAssertEqual(report.projects.first?.time, 3600)
    }

    func testRecentLogReturnsAddedFrames() throws {
        let client = makeClient()
        let start = dayStart.addingTimeInterval(9 * 3600)
        try client.add(Accrual.addCommand(project: "logged", start: start, accruedSeconds: 1800, tags: ["t"], timeZone: utc)!)
        let log = try client.recentLog()
        XCTAssertEqual(log.first?.project, "logged")
        XCTAssertEqual(log.first?.tags, ["t"])
    }

    /// Compatibility proof: a real `watson` CLI must read frames we wrote.
    /// Skipped where watson isn't installed.
    func testWrittenFramesReadableByWatsonCLI() throws {
        let watsonPath = "/opt/homebrew/bin/watson"
        try XCTSkipUnless(FileManager.default.isExecutableFile(atPath: watsonPath), "watson CLI not installed")

        // Real local tz + now so watson's local `--day` lines up with ours.
        let client = FileWatsonClient(dataDirectory: tempDir, timeZone: .current, now: { Date() })
        let start = Calendar.current.startOfDay(for: Date()).addingTimeInterval(8 * 3600)
        try client.add(Accrual.addCommand(project: "conan-itest", start: start, accruedSeconds: 3600, tags: ["meeting"], timeZone: .current)!)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: watsonPath)
        process.arguments = ["report", "--day", "--json"]
        var environment = ProcessInfo.processInfo.environment
        environment["WATSON_DIR"] = tempDir.path
        process.environment = environment
        process.standardInput = FileHandle.nullDevice
        let pipe = Pipe()
        process.standardOutput = pipe
        try process.run()
        let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        process.waitUntilExit()

        XCTAssertTrue(output.contains("conan-itest"), "watson did not read our frame: \(output)")
        XCTAssertTrue(output.contains("3600"), "watson reported unexpected time: \(output)")
    }
}
