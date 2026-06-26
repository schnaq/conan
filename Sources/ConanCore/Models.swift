import Foundation

/// The currently-running main project (its open interval).
public struct MainSession: Codable, Equatable, Sendable {
    public var project: String
    public var start: Date

    public init(project: String, start: Date) {
        self.project = project
        self.start = start
    }
}

/// A side project that accrues a fraction of main time while switched on.
/// `percent` is a fraction (e.g. 0.10 for 10%). `intervalStart` marks the start
/// of the current open accrual interval (forward-only).
public struct SideProject: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var percent: Double
    public var intervalStart: Date

    public init(id: UUID = UUID(), name: String, percent: Double, intervalStart: Date) {
        self.id = id
        self.name = name
        self.percent = percent
        self.intervalStart = intervalStart
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
