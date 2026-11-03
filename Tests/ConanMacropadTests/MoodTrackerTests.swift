import XCTest
@testable import ConanMacropad

final class MoodTrackerTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)

    /// Ticks once at t0 (starting the not-tracking streak), then once at t0 + seconds.
    private func idleMood(after seconds: TimeInterval) -> Mood {
        var tracker = MoodTracker()
        _ = tracker.tick(now: t0, idleSeconds: 0, isRunning: false, startedAt: nil)
        return tracker.tick(now: t0.addingTimeInterval(seconds), idleSeconds: 0, isRunning: false, startedAt: nil)
    }

    func testBoredUntil120s() {
        XCTAssertEqual(idleMood(after: 0), .bored)
        XCTAssertEqual(idleMood(after: 119), .bored)
    }

    func testCoffeeFrom120s() { XCTAssertEqual(idleMood(after: 120), .coffee) }
    func testDemandFrom300s() { XCTAssertEqual(idleMood(after: 300), .demand) }
    func testAlertFrom600s() { XCTAssertEqual(idleMood(after: 600), .alert) }

    func testSleepWhenAwayRegardlessOfTimer() {
        var tracker = MoodTracker()
        XCTAssertEqual(tracker.tick(now: t0, idleSeconds: 120, isRunning: false, startedAt: nil), .sleep)
        XCTAssertEqual(tracker.tick(now: t0, idleSeconds: 120, isRunning: true, startedAt: t0.addingTimeInterval(-600)), .sleep)
    }

    func testComingBackRestartsAtBored() {
        var tracker = MoodTracker()
        _ = tracker.tick(now: t0, idleSeconds: 0, isRunning: false, startedAt: nil)
        _ = tracker.tick(now: t0.addingTimeInterval(400), idleSeconds: 200, isRunning: false, startedAt: nil) // away
        XCTAssertEqual(tracker.tick(now: t0.addingTimeInterval(410), idleSeconds: 0, isRunning: false, startedAt: nil), .bored)
    }

    func testTrackingResetsTheStreak() {
        var tracker = MoodTracker()
        _ = tracker.tick(now: t0, idleSeconds: 0, isRunning: false, startedAt: nil)
        _ = tracker.tick(now: t0.addingTimeInterval(400), idleSeconds: 0, isRunning: true, startedAt: t0.addingTimeInterval(390))
        XCTAssertEqual(tracker.tick(now: t0.addingTimeInterval(410), idleSeconds: 0, isRunning: false, startedAt: nil), .bored)
    }

    func testStartForTwoSecondsThenWork() {
        var tracker = MoodTracker()
        XCTAssertEqual(tracker.tick(now: t0.addingTimeInterval(1.9), idleSeconds: 0, isRunning: true, startedAt: t0), .start)
        XCTAssertEqual(tracker.tick(now: t0.addingTimeInterval(2), idleSeconds: 0, isRunning: true, startedAt: t0), .work)
    }
}
