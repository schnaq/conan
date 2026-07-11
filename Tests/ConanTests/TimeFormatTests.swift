import XCTest
@testable import ConanCore

final class TimeFormatTests: XCTestCase {
    func testClockZeroIsZeroPadded() {
        XCTAssertEqual(TimeFormat.clock(0), "00:00")
    }

    func testClockDropsSeconds() {
        XCTAssertEqual(TimeFormat.clock(59), "00:00")
    }

    func testClockMinutesAndHours() {
        XCTAssertEqual(TimeFormat.clock(3599), "00:59")
        XCTAssertEqual(TimeFormat.clock(3661), "01:01")
    }

    func testClockNegativeClampsToZero() {
        XCTAssertEqual(TimeFormat.clock(-5), "00:00")
    }

    func testHumanUnchanged() {
        XCTAssertEqual(TimeFormat.human(3661), "1h 1m")
        XCTAssertEqual(TimeFormat.human(125), "2m")
        XCTAssertEqual(TimeFormat.human(45), "45s")
    }
}
