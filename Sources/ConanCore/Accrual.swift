import Foundation

/// Arguments for one `watson add` invocation (a single completed frame).
public struct WatsonAddCommand: Equatable, Sendable {
    public let project: String
    public let from: String   // local wall-clock "yyyy-MM-dd HH:mm:ss"
    public let to: String
    public let tags: [String]

    public init(project: String, from: String, to: String, tags: [String]) {
        self.project = project
        self.from = from
        self.to = to
        self.tags = tags
    }
}

/// Pure time-allocation math + watson frame materialization. No I/O, no global
/// state — this is the fully unit-tested core of Conan.
public enum Accrual {
    /// Tag applied to every auto-allocated side-project frame so it is
    /// identifiable in `watson report`/`watson log`.
    public static let sideTag = "conan"

    /// Whole seconds accrued for an interval at a given fraction (0…1+).
    /// Rounds to the nearest second at the last moment (watson stores int epochs).
    public static func accruedSeconds(intervalSeconds: Double, percent: Double) -> Int {
        guard intervalSeconds > 0, percent > 0 else { return 0 }
        return Int((percent * intervalSeconds).rounded())
    }

    /// Local wall-clock string that `watson add --from/--to` expects.
    public static func watsonDateString(_ date: Date, timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.string(from: date)
    }

    /// Build the `watson add` command for an accrued span, or nil if it must be
    /// skipped. Sub-second / zero-length frames are skipped because watson stores
    /// them as `0.0` and they only pollute reports.
    public static func addCommand(
        project: String,
        start: Date,
        accruedSeconds: Int,
        tags: [String] = [],
        timeZone: TimeZone = .current
    ) -> WatsonAddCommand? {
        guard accruedSeconds >= 1 else { return nil }
        let end = start.addingTimeInterval(TimeInterval(accruedSeconds))
        guard end > start else { return nil }   // clock-change / DST guard
        return WatsonAddCommand(
            project: project,
            from: watsonDateString(start, timeZone: timeZone),
            to: watsonDateString(end, timeZone: timeZone),
            tags: tags
        )
    }

    /// The set of watson frames to write when closing intervals at time `t`.
    /// Side projects flush first (each tagged `conan`), then the main project at
    /// 100%. Forward-only: each side accrues only from its own `intervalStart`.
    /// Tiny (<1s) intervals are dropped.
    public static func flushCommands(
        main: MainSession?,
        sides: [SideProject],
        at t: Date,
        timeZone: TimeZone = .current
    ) -> [WatsonAddCommand] {
        var commands: [WatsonAddCommand] = []

        for side in sides {
            let secs = accruedSeconds(
                intervalSeconds: t.timeIntervalSince(side.intervalStart),
                percent: side.percent
            )
            // User tags + the auto `conan` tag (don't duplicate if typed).
            let tags = side.tags.contains(sideTag) ? side.tags : side.tags + [sideTag]
            if let command = addCommand(
                project: side.name,
                start: side.intervalStart,
                accruedSeconds: secs,
                tags: tags,
                timeZone: timeZone
            ) {
                commands.append(command)
            }
        }

        if let main {
            let secs = accruedSeconds(
                intervalSeconds: t.timeIntervalSince(main.start),
                percent: 1.0
            )
            if let command = addCommand(
                project: main.project,
                start: main.start,
                accruedSeconds: secs,
                tags: main.tags,
                timeZone: timeZone
            ) {
                commands.append(command)
            }
        }

        return commands
    }
}
