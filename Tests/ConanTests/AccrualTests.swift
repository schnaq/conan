import XCTest
@testable import ConanCore

final class AccrualTests: XCTestCase {
    private let utc = TimeZone(identifier: "UTC")!
    // 1_700_000_000 == 2023-11-14 22:13:20 UTC
    private let base = Date(timeIntervalSince1970: 1_700_000_000)

    func testAccruedSecondsBasic() {
        XCTAssertEqual(Accrual.accruedSeconds(intervalSeconds: 3600, percent: 0.1), 360)
        XCTAssertEqual(Accrual.accruedSeconds(intervalSeconds: 3600, percent: 1.0), 3600)
        XCTAssertEqual(Accrual.accruedSeconds(intervalSeconds: 3600, percent: 0.25), 900)
    }

    func testAccruedSecondsRoundsToNearest() {
        XCTAssertEqual(Accrual.accruedSeconds(intervalSeconds: 9, percent: 0.1), 1)   // 0.9 -> 1
        XCTAssertEqual(Accrual.accruedSeconds(intervalSeconds: 4, percent: 0.1), 0)   // 0.4 -> 0
    }

    func testAccruedSecondsGuards() {
        XCTAssertEqual(Accrual.accruedSeconds(intervalSeconds: 0, percent: 0.5), 0)
        XCTAssertEqual(Accrual.accruedSeconds(intervalSeconds: -100, percent: 0.5), 0)
        XCTAssertEqual(Accrual.accruedSeconds(intervalSeconds: 3600, percent: 0), 0)
    }

    func testWatsonDateString() {
        XCTAssertEqual(Accrual.watsonDateString(base, timeZone: utc), "2023-11-14 22:13:20")
    }

    func testAddCommandSkipsSubSecond() {
        XCTAssertNil(Accrual.addCommand(project: "x", start: base, accruedSeconds: 0, timeZone: utc))
    }

    func testAddCommandBuildsForwardSpan() {
        let command = Accrual.addCommand(
            project: "demo", start: base, accruedSeconds: 360, tags: ["conan"], timeZone: utc
        )
        XCTAssertEqual(command?.project, "demo")
        XCTAssertEqual(command?.from, "2023-11-14 22:13:20")
        XCTAssertEqual(command?.to, "2023-11-14 22:19:20")   // +360s
        XCTAssertEqual(command?.tags, ["conan"])
    }

    func testFlushCommandsMainAndSides() {
        let main = MainSession(project: "main", start: base)
        let side = SideProject(name: "side", percent: 0.1, intervalStart: base.addingTimeInterval(600))
        let stop = base.addingTimeInterval(3600)   // 1h main

        let commands = Accrual.flushCommands(main: main, sides: [side], at: stop, timeZone: utc)

        XCTAssertEqual(commands.count, 2)
        // side first: active 3000s * 0.1 = 300s, tagged conan, anchored at side start
        XCTAssertEqual(commands[0].project, "side")
        XCTAssertEqual(commands[0].tags, ["conan"])
        XCTAssertEqual(commands[0].from, "2023-11-14 22:23:20")   // base + 600
        XCTAssertEqual(commands[0].to, "2023-11-14 22:28:20")     // + 300
        // main: 3600s * 1.0, untagged, [start, stop]
        XCTAssertEqual(commands[1].project, "main")
        XCTAssertEqual(commands[1].tags, [])
        XCTAssertEqual(commands[1].from, "2023-11-14 22:13:20")
        XCTAssertEqual(commands[1].to, "2023-11-14 23:13:20")
    }

    func testFlushCommandsCarryTags() {
        let main = MainSession(project: "main", start: base, tags: ["meeting"])
        let side = SideProject(name: "side", percent: 0.5, intervalStart: base, tags: ["review"])

        let commands = Accrual.flushCommands(main: main, sides: [side], at: base.addingTimeInterval(3600), timeZone: utc)

        XCTAssertEqual(commands[0].project, "side")
        XCTAssertEqual(commands[0].tags, ["review", "conan"])   // user tag + auto conan
        XCTAssertEqual(commands[1].project, "main")
        XCTAssertEqual(commands[1].tags, ["meeting"])
    }

    func testFlushDropsTinySide() {
        let main = MainSession(project: "main", start: base)
        // side active only 4s at 10% -> 0.4s -> dropped
        let side = SideProject(name: "tiny", percent: 0.1, intervalStart: base.addingTimeInterval(3596))
        let stop = base.addingTimeInterval(3600)

        let commands = Accrual.flushCommands(main: main, sides: [side], at: stop, timeZone: utc)

        XCTAssertEqual(commands.count, 1)        // only main survives
        XCTAssertEqual(commands[0].project, "main")
    }
}
