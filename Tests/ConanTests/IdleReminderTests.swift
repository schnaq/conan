import XCTest
@testable import ConanCore

final class IdleReminderTests: XCTestCase {
    private let base = Date(timeIntervalSince1970: 1_700_000_000)
    private func at(_ seconds: TimeInterval) -> Date { base.addingTimeInterval(seconds) }

    func testFiresOnceAfterFiveActiveMinutes() {
        var reminder = IdleReminder(idleResetThreshold: 120, reminderDelay: 300)
        // Active (small idle), not tracking, enabled.
        XCTAssertFalse(reminder.tick(now: at(0),   idleSeconds: 5, isTracking: false, enabled: true)) // streak begins
        XCTAssertFalse(reminder.tick(now: at(270), idleSeconds: 5, isTracking: false, enabled: true)) // < 300
        XCTAssertTrue(reminder.tick(now: at(300),  idleSeconds: 5, isTracking: false, enabled: true)) // fire
        XCTAssertFalse(reminder.tick(now: at(330), idleSeconds: 5, isTracking: false, enabled: true)) // no repeat
    }

    func testDisabledNeverFires() {
        var reminder = IdleReminder()
        XCTAssertFalse(reminder.tick(now: at(0),   idleSeconds: 5, isTracking: false, enabled: false))
        XCTAssertFalse(reminder.tick(now: at(600), idleSeconds: 5, isTracking: false, enabled: false))
    }

    func testTrackingResetsStreak() {
        var reminder = IdleReminder(idleResetThreshold: 120, reminderDelay: 300)
        XCTAssertFalse(reminder.tick(now: at(0),   idleSeconds: 5, isTracking: false, enabled: true))
        XCTAssertFalse(reminder.tick(now: at(100), idleSeconds: 5, isTracking: true,  enabled: true)) // tracking resets
        // Stops tracking; a fresh streak starts at 120, so the reminder only fires 300s later.
        XCTAssertFalse(reminder.tick(now: at(120), idleSeconds: 5, isTracking: false, enabled: true))
        XCTAssertFalse(reminder.tick(now: at(400), idleSeconds: 5, isTracking: false, enabled: true)) // 280 < 300
        XCTAssertTrue(reminder.tick(now: at(420),  idleSeconds: 5, isTracking: false, enabled: true)) // fire
    }

    func testSteppingAwayResetsAndReArms() {
        var reminder = IdleReminder(idleResetThreshold: 120, reminderDelay: 300)
        XCTAssertFalse(reminder.tick(now: at(0),   idleSeconds: 5,   isTracking: false, enabled: true))
        XCTAssertTrue(reminder.tick(now: at(300),  idleSeconds: 5,   isTracking: false, enabled: true)) // fire #1
        // User steps away (idle past threshold) → reset + re-arm.
        XCTAssertFalse(reminder.tick(now: at(330), idleSeconds: 200, isTracking: false, enabled: true))
        // Returns; new streak from 360 fires again 300s later.
        XCTAssertFalse(reminder.tick(now: at(360), idleSeconds: 5,   isTracking: false, enabled: true))
        XCTAssertTrue(reminder.tick(now: at(660),  idleSeconds: 5,   isTracking: false, enabled: true)) // fire #2
    }
}
