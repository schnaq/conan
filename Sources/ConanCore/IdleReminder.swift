import Foundation

/// Pure state machine deciding when to fire the "you're not tracking" reminder.
///
/// Tick it periodically with the current time, the system input-idle seconds,
/// and whether a project is being tracked. It returns `true` exactly once per
/// "active streak" — when the user has been continuously present (using the Mac,
/// not tracking) for `reminderDelay`. The streak resets when the user starts
/// tracking, steps away (idle ≥ `idleResetThreshold`), or disables the setting,
/// which re-arms the reminder for the next streak.
public struct IdleReminder {
    public let idleResetThreshold: TimeInterval   // treat as "away" when idle ≥ this
    public let reminderDelay: TimeInterval        // remind after this much active-not-tracking

    private var streakStart: Date?
    private var reminded: Bool

    public init(idleResetThreshold: TimeInterval = 120, reminderDelay: TimeInterval = 300) {
        self.idleResetThreshold = idleResetThreshold
        self.reminderDelay = reminderDelay
        self.streakStart = nil
        self.reminded = false
    }

    /// Returns `true` when a reminder should be dispatched on this tick.
    public mutating func tick(
        now: Date,
        idleSeconds: TimeInterval,
        isTracking: Bool,
        enabled: Bool
    ) -> Bool {
        // Disabled, tracking, or stepped away → end the streak and re-arm.
        if !enabled || isTracking || idleSeconds >= idleResetThreshold {
            streakStart = nil
            reminded = false
            return false
        }

        // User is present and not tracking.
        let start = streakStart ?? now
        streakStart = start

        if !reminded, now.timeIntervalSince(start) >= reminderDelay {
            reminded = true
            return true
        }
        return false
    }
}
