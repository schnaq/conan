import Foundation

public enum WatsonError: Error, CustomStringConvertible {
    case notFound
    case failed(Int32, String)
    case badOutput

    public var description: String {
        switch self {
        case .notFound: return "watson binary not found"
        case let .failed(code, message): return "watson exited \(code): \(message)"
        case .badOutput: return "could not parse watson output"
        }
    }
}

/// Abstraction over the `watson` CLI so session logic can be tested with a mock.
public protocol WatsonClient: Sendable {
    func version() throws -> String
    func projects() throws -> [String]
    func add(_ command: WatsonAddCommand) throws
    func reportDay() throws -> WatsonReport
    func recentLog() throws -> [WatsonLogFrame]
}

/// Real client: shells out to the `watson` binary. All invocations are
/// serialized through one queue because watson does an unlocked
/// read-modify-write of its `frames` file — concurrent `add`s could clobber.
public final class ProcessWatsonClient: WatsonClient, @unchecked Sendable {
    private let binaryPath: String
    private let queue = DispatchQueue(label: "com.schnaq.conan.watson")

    /// Resolve the watson binary. GUI apps don't inherit the shell `PATH`, so we
    /// probe the known Homebrew locations.
    public static func resolveBinaryPath() -> String? {
        ["/opt/homebrew/bin/watson", "/usr/local/bin/watson"]
            .first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    public init?(binaryPath: String? = ProcessWatsonClient.resolveBinaryPath()) {
        guard let binaryPath else { return nil }
        self.binaryPath = binaryPath
    }

    public func version() throws -> String {
        try run(["--version"]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public func projects() throws -> [String] {
        try run(["projects"])
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    public func add(_ command: WatsonAddCommand) throws {
        // No -c/-b flags: those ENABLE an interactive confirm prompt that aborts
        // non-interactively. watson creates unknown projects/tags silently.
        var args = ["add", "--from", command.from, "--to", command.to, command.project]
        args += command.tags.map { "+\($0)" }
        _ = try run(args)
    }

    public func reportDay() throws -> WatsonReport {
        let output = try run(["report", "--day", "--json"])
        guard let data = output.data(using: .utf8) else { throw WatsonError.badOutput }
        return try JSONDecoder().decode(WatsonReport.self, from: data)
    }

    public func recentLog() throws -> [WatsonLogFrame] {
        // Last 30 days of frames — enough to surface recently-used project+tag variants.
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        let from = formatter.string(from: Date().addingTimeInterval(-30 * 24 * 60 * 60))
        let output = try run(["log", "--json", "--from", from])
        guard let data = output.data(using: .utf8) else { throw WatsonError.badOutput }
        return try JSONDecoder().decode([WatsonLogFrame].self, from: data)
    }

    @discardableResult
    private func run(_ arguments: [String]) throws -> String {
        try queue.sync {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: binaryPath)
            process.arguments = arguments
            process.standardInput = FileHandle.nullDevice   // never block on a prompt

            let stdout = Pipe()
            let stderr = Pipe()
            process.standardOutput = stdout
            process.standardError = stderr

            try process.run()
            let outData = stdout.fileHandleForReading.readDataToEndOfFile()
            let errData = stderr.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()

            if process.terminationStatus != 0 {
                let message = String(data: errData, encoding: .utf8) ?? ""
                throw WatsonError.failed(
                    process.terminationStatus,
                    message.trimmingCharacters(in: .whitespacesAndNewlines)
                )
            }
            return String(data: outData, encoding: .utf8) ?? ""
        }
    }
}
