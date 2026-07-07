import Foundation

/// The currently-running main project (its open interval) and its tags.
public struct MainSession: Codable, Equatable, Sendable {
    public var project: String
    public var start: Date
    public var tags: [String]
    /// True when this session was adopted from a terminal `watson start` rather
    /// than started inside Conan (drives a "started in terminal" UI hint).
    public var wasAdopted: Bool

    public init(project: String, start: Date, tags: [String] = [], wasAdopted: Bool = false) {
        self.project = project
        self.start = start
        self.tags = tags
        self.wasAdopted = wasAdopted
    }

    // Custom decode so state.json written by an older version (no `tags` /
    // `wasAdopted`) still recovers cleanly.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        project = try container.decode(String.self, forKey: .project)
        start = try container.decode(Date.self, forKey: .start)
        tags = try container.decodeIfPresent([String].self, forKey: .tags) ?? []
        wasAdopted = try container.decodeIfPresent(Bool.self, forKey: .wasAdopted) ?? false
    }
}

/// A side project that accrues a fraction of main time while switched on.
/// `percent` is a fraction (e.g. 0.10 for 10%). `intervalStart` marks the start
/// of the current open accrual interval (forward-only). `tags` are user tags
/// (the auto `conan` tag is added at flush time).
public struct SideProject: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var percent: Double
    public var intervalStart: Date
    public var tags: [String]

    public init(id: UUID = UUID(), name: String, percent: Double, intervalStart: Date, tags: [String] = []) {
        self.id = id
        self.name = name
        self.percent = percent
        self.intervalStart = intervalStart
        self.tags = tags
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        percent = try container.decode(Double.self, forKey: .percent)
        intervalStart = try container.decode(Date.self, forKey: .intervalStart)
        tags = try container.decodeIfPresent([String].self, forKey: .tags) ?? []
    }
}

/// Everything persisted to `state.json` for crash recovery. Dates are encoded as
/// epoch seconds (the coder sets `.secondsSince1970`).
public struct PersistedState: Codable, Equatable, Sendable {
    public var main: MainSession?
    public var sideProjects: [SideProject]
    public var lastSeen: Date

    public init(main: MainSession?, sideProjects: [SideProject], lastSeen: Date) {
        self.main = main
        self.sideProjects = sideProjects
        self.lastSeen = lastSeen
    }
}
