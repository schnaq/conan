import Foundation

/// Abstraction over watson operations so the session logic can be unit-tested
/// with a mock and backed by different implementations. Conan's implementation
/// is `FileWatsonClient`, which reads/writes watson's data files directly.
public protocol WatsonClient: Sendable {
    func version() throws -> String
    func projects() throws -> [String]
    func add(_ command: WatsonAddCommand) throws
    func reportDay() throws -> WatsonReport
    func recentLog() throws -> [WatsonLogFrame]

    // MARK: Running frame (watson's `state` file) — two-way sync with the CLI.

    /// The frame watson currently considers running, or nil when idle (`{}`).
    func runningFrame() throws -> WatsonRunningFrame?
    /// Write watson's running-frame state (so the terminal sees Conan's session).
    func setRunningFrame(_ frame: WatsonRunningFrame) throws
    /// Clear watson's running-frame state to idle (`{}`).
    func clearRunningFrame() throws
    /// Stop time of the completed frame watson wrote for a given project+start
    /// epoch (used to pin side accrual when `watson stop` closed the main frame).
    /// Nil when no matching frame exists.
    func stopTime(project: String, startEpoch: Int) throws -> Date?
}
