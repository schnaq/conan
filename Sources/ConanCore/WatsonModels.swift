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
