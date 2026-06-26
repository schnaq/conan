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
}
