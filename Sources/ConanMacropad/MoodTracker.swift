import Foundation

/// schnaqqi's mood on the MacroPad (names match the sprite sheets in schnaq/assets).
enum Mood: String {
    case start, work, bored, coffee, demand, alert, sleep
}

/// Decides schnaqqi's mood. Not tracking while at the Mac escalates over time;
/// stepping away or starting a timer resets that streak.
struct MoodTracker {
    // Calibration knobs: seconds.
    static let awayAfter: TimeInterval = 120
    static let startShownFor: TimeInterval = 2
    static let coffeeAfter: TimeInterval = 120
    static let demandAfter: TimeInterval = 300
    static let alertAfter: TimeInterval = 600

    private var notTrackingSince: Date?

    mutating func tick(now: Date, idleSeconds: TimeInterval, isRunning: Bool, startedAt: Date?) -> Mood {
        if idleSeconds >= Self.awayAfter {
            notTrackingSince = nil
            return .sleep
        }
        if isRunning {
            notTrackingSince = nil
            if let startedAt, now.timeIntervalSince(startedAt) < Self.startShownFor { return .start }
            return .work
        }
        let since = notTrackingSince ?? now
        notTrackingSince = since
        switch now.timeIntervalSince(since) {
        case ..<Self.coffeeAfter: return .bored
        case ..<Self.demandAfter: return .coffee
        case ..<Self.alertAfter: return .demand
        default: return .alert
        }
    }
}
