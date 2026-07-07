import Foundation

/// Decoded shape of `watson report --day --json`. All `time` values are in
/// float seconds.
public struct WatsonReport: Codable, Equatable, Sendable {
    public let projects: [Project]
    public let time: Double
    public let timespan: Timespan

    public struct Project: Codable, Equatable, Sendable, Identifiable {
        public let name: String
        public let tags: [Tag]
        public let time: Double

        public var id: String { name }
    }

    public struct Tag: Codable, Equatable, Sendable {
        public let name: String
        public let time: Double
    }

    public struct Timespan: Codable, Equatable, Sendable {
        public let from: String   // ISO 8601 with timezone offset
        public let to: String
    }
}

/// Watson's currently-running frame — the contents of watson's `state` file
/// (`{project, start, tags}`; an empty `{}` means nothing is running). Conan
/// reads this to reflect a terminal `watson start`, and writes it so the terminal
/// sees Conan's own session and `watson stop` can close it.
public struct WatsonRunningFrame: Equatable, Sendable {
    public let project: String
    public let start: Date
    public let tags: [String]

    public init(project: String, start: Date, tags: [String] = []) {
        self.project = project
        self.start = start
        self.tags = tags
    }
}

/// One frame from `watson log --json` (only the fields Conan needs). Extra keys
/// (id, stop) are ignored.
public struct WatsonLogFrame: Codable, Equatable, Sendable {
    public let project: String
    public let tags: [String]
    public let start: String   // ISO 8601; used for recency ordering

    public init(project: String, tags: [String], start: String) {
        self.project = project
        self.tags = tags
        self.start = start
    }
}
