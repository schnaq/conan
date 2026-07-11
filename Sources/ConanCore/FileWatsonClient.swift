import Foundation

/// A self-contained `WatsonClient` that reads and writes watson's own data file
/// directly — no `watson` binary or Python required. Fully format-compatible:
/// the `frames` file it maintains is the same one the `watson` CLI uses, so
/// `watson report --day` keeps working for anyone who also has watson installed,
/// and data is shared both ways.
///
/// It mirrors watson's `report --day` semantics: each frame is clipped to the
/// local day and the clipped duration is summed (per project, and per tag for
/// frames carrying that tag).
public final class FileWatsonClient: WatsonClient, @unchecked Sendable {
    private let framesURL: URL
    private let stateURL: URL
    private let timeZone: TimeZone
    private let now: () -> Date
    private let queue = DispatchQueue(label: "com.schnaq.conan.filewatson")

    public init(
        dataDirectory: URL? = nil,
        timeZone: TimeZone = .current,
        now: @escaping () -> Date = { Date() }
    ) {
        let directory = dataDirectory ?? FileWatsonClient.defaultDataDirectory()
        self.framesURL = directory.appendingPathComponent("frames")
        self.stateURL = directory.appendingPathComponent("state")
        self.timeZone = timeZone
        self.now = now
    }

    /// The same location watson uses on macOS: `$WATSON_DIR` if set, else
    /// `~/Library/Application Support/watson`.
    public static func defaultDataDirectory() -> URL {
        if let env = ProcessInfo.processInfo.environment["WATSON_DIR"], !env.isEmpty {
            return URL(fileURLWithPath: env, isDirectory: true)
        }
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("watson", isDirectory: true)
    }

    // MARK: - WatsonClient

    public func version() throws -> String { "conan-builtin" }

    public func add(_ command: WatsonAddCommand) throws {
        let start = Int(parseLocal(command.from).timeIntervalSince1970)
        let stop = Int(parseLocal(command.to).timeIntervalSince1970)
        let id = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        let updatedAt = Int(now().timeIntervalSince1970)
        try queue.sync {
            var frames = try loadRawFrames()
            frames.append([start, stop, command.project, id, command.tags, updatedAt])
            try writeRawFrames(frames)
        }
    }

    public func projects() throws -> [String] {
        let frames = try queue.sync { try loadFrames() }
        return Array(Set(frames.map(\.project))).sorted()
    }

    public func recentLog() throws -> [WatsonLogFrame] {
        let frames = try queue.sync { try loadFrames() }
        let cutoff = now().addingTimeInterval(-30 * 24 * 60 * 60)
        let iso = isoFormatter()
        return frames
            .filter { $0.start >= cutoff }
            .map { WatsonLogFrame(project: $0.project, tags: $0.tags, start: iso.string(from: $0.start)) }
    }

    public func reportDay() throws -> WatsonReport {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let dayStart = calendar.startOfDay(for: now())
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart.addingTimeInterval(86_400)
        return try report(from: dayStart, to: dayEnd)
    }

    /// Weekly totals for the ISO week (Monday 00:00 → next Monday 00:00 in the
    /// client's time zone) containing `reference`.
    public func reportWeek(containing reference: Date) throws -> WatsonReport {
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = timeZone
        let week = calendar.dateInterval(of: .weekOfYear, for: reference)
            ?? DateInterval(start: calendar.startOfDay(for: reference), duration: 7 * 86_400)
        return try report(from: week.start, to: week.end)
    }

    /// Watson-style clip-and-sum aggregation over an arbitrary
    /// `[rangeStart, rangeEnd)` window: each frame is clipped to the range and
    /// the clipped duration summed per project (and per tag).
    private func report(from rangeStart: Date, to rangeEnd: Date) throws -> WatsonReport {
        let frames = try queue.sync { try loadFrames() }

        struct Aggregate { var time: Double = 0; var tags: [String: Double] = [:] }
        var byProject: [String: Aggregate] = [:]
        var total: Double = 0

        for frame in frames {
            guard frame.start < rangeEnd, frame.stop > rangeStart else { continue }   // overlaps the range
            let clippedStart = max(frame.start, rangeStart)
            let clippedStop = min(frame.stop, rangeEnd)
            let duration = clippedStop.timeIntervalSince(clippedStart)
            guard duration > 0 else { continue }

            var aggregate = byProject[frame.project] ?? Aggregate()
            aggregate.time += duration
            for tag in frame.tags { aggregate.tags[tag, default: 0] += duration }
            byProject[frame.project] = aggregate
            total += duration
        }

        let projects = byProject.sorted { $0.key < $1.key }.map { name, aggregate in
            WatsonReport.Project(
                name: name,
                tags: aggregate.tags.sorted { $0.key < $1.key }.map { WatsonReport.Tag(name: $0.key, time: $0.value) },
                time: aggregate.time
            )
        }

        let iso = isoFormatter()
        return WatsonReport(
            projects: projects,
            time: total,
            timespan: WatsonReport.Timespan(from: iso.string(from: rangeStart), to: iso.string(from: rangeEnd))
        )
    }

    // MARK: - Running frame (watson `state` file)

    public func runningFrame() throws -> WatsonRunningFrame? {
        queue.sync {
            guard let data = try? Data(contentsOf: stateURL), !data.isEmpty,
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let project = object["project"] as? String, !project.isEmpty,
                  let start = object["start"] as? NSNumber
            else { return nil }
            let tags = (object["tags"] as? [String]) ?? []
            return WatsonRunningFrame(
                project: project,
                start: Date(timeIntervalSince1970: start.doubleValue),
                tags: tags
            )
        }
    }

    public func setRunningFrame(_ frame: WatsonRunningFrame) throws {
        try queue.sync {
            try writeState([
                "project": frame.project,
                "start": Int(frame.start.timeIntervalSince1970),   // watson stores int epochs
                "tags": frame.tags,
            ])
        }
    }

    public func clearRunningFrame() throws {
        try queue.sync { try writeState([:]) }   // watson's idle state is `{}`
    }

    public func stopTime(project: String, startEpoch: Int) throws -> Date? {
        let frames = try queue.sync { try loadFrames() }
        return frames
            .filter { $0.project == project && Int($0.start.timeIntervalSince1970) == startEpoch }
            .max(by: { $0.stop < $1.stop })?
            .stop
    }

    private func writeState(_ object: [String: Any]) throws {
        try FileManager.default.createDirectory(
            at: stateURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try JSONSerialization.data(withJSONObject: object)
        try data.write(to: stateURL, options: .atomic)
    }

    // MARK: - Frame I/O

    private struct StoredFrame {
        let start: Date
        let stop: Date
        let project: String
        let tags: [String]
    }

    private func loadFrames() throws -> [StoredFrame] {
        try loadRawFrames().compactMap { row in
            guard row.count >= 5,
                  let startNumber = row[0] as? NSNumber,
                  let stopNumber = row[1] as? NSNumber,
                  let project = row[2] as? String,
                  let tags = row[4] as? [String]
            else { return nil }
            return StoredFrame(
                start: Date(timeIntervalSince1970: startNumber.doubleValue),
                stop: Date(timeIntervalSince1970: stopNumber.doubleValue),
                project: project,
                tags: tags
            )
        }
    }

    private func loadRawFrames() throws -> [[Any]] {
        guard let data = try? Data(contentsOf: framesURL), !data.isEmpty else { return [] }
        let object = try JSONSerialization.jsonObject(with: data)
        return (object as? [[Any]]) ?? []
    }

    private func writeRawFrames(_ frames: [[Any]]) throws {
        try FileManager.default.createDirectory(
            at: framesURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try JSONSerialization.data(withJSONObject: frames, options: [.prettyPrinted])
        try data.write(to: framesURL, options: .atomic)
    }

    // MARK: - Helpers

    /// Parse a local wall-clock "yyyy-MM-dd HH:mm:ss" string (the form
    /// `WatsonAddCommand` carries) back into an absolute date.
    private func parseLocal(_ string: String) -> Date {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.date(from: string) ?? now()
    }

    private func isoFormatter() -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = timeZone
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }
}
