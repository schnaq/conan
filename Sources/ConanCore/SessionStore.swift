import Foundation
import Combine

/// Single source of truth for the running session. Conan owns all timing and
/// writes completed frames to watson when intervals close — it never calls
/// `watson start`/`stop` and never touches watson's `state`.
@MainActor
public final class SessionStore: ObservableObject {
    @Published public private(set) var main: MainSession?
    @Published public private(set) var sideProjects: [SideProject] = []
    @Published public private(set) var lastSetup: SessionSetup?
    @Published public private(set) var todayReport: WatsonReport?
    @Published public private(set) var projects: [String] = []
    @Published public private(set) var recentCombos: [ProjectTags] = []
    @Published public private(set) var lastError: String?

    public let watsonAvailable: Bool

    private let watson: WatsonClient?
    private let stateURL: URL
    private let clock: () -> Date
    private var heartbeat: Timer?
    private var idleReminder = IdleReminder()

    private static let heartbeatInterval: TimeInterval = 30

    /// UserDefaults key for the "remind me when not tracking" setting (shared
    /// with the SwiftUI toggle via `@AppStorage`).
    public static let remindWhenIdleDefaultsKey = "conan.remindWhenIdle"

    public init(
        watson: WatsonClient?,
        stateURL: URL = SessionStore.defaultStateURL(),
        clock: @escaping () -> Date = { Date() }
    ) {
        self.watson = watson
        self.watsonAvailable = (watson != nil)
        self.stateURL = stateURL
        self.clock = clock
        recoverOnLaunch()
        startHeartbeat()
    }

    public var isRunning: Bool { main != nil }

    // MARK: - Main project

    public func startMain(project: String, tags: [String] = []) {
        let name = project.trimmingCharacters(in: .whitespacesAndNewlines)
        guard main == nil, !name.isEmpty else { return }
        let session = MainSession(project: name, start: clock(), tags: tags)
        main = session
        syncRunningFrame(session)   // let the terminal (`watson status`/`stop`) see it
        persist()
    }

    /// Stop the main project and every side project at once. Remembers the
    /// stopped setup so "Resume all" can restart it.
    public func stopAll() {
        guard let main else { return }
        lastSetup = SessionSetup(main: main, sides: sideProjects)
        let commands = Accrual.flushCommands(main: main, sides: sideProjects, at: clock())
        // Drop watson's baton *before* niling main so a concurrent reconcile can't
        // re-adopt the frame we're closing, and `watson stop` can't re-write it.
        dropRunningFrame()
        self.main = nil
        sideProjects = []
        persist()
        run(commands)
    }

    /// Restart the exact setup that was running at the last "Stop all" (or
    /// interrupted by a quit/crash), with fresh timestamps.
    public func resumeAll() {
        guard main == nil, let setup = lastSetup else { return }
        startMain(project: setup.mainProject, tags: setup.mainTags)
        for side in setup.sides {
            addSide(project: side.name, percent: side.percent, tags: side.tags)
        }
    }

    // MARK: - Side projects

    public func addSide(project: String, percent: Double, tags: [String] = []) {
        let name = project.trimmingCharacters(in: .whitespacesAndNewlines)
        guard main != nil, !name.isEmpty, percent > 0 else { return }
        sideProjects.append(SideProject(name: name, percent: percent, intervalStart: clock(), tags: tags))
        persist()
    }

    public func stopSide(_ id: UUID) {
        guard let index = sideProjects.firstIndex(where: { $0.id == id }) else { return }
        let side = sideProjects.remove(at: index)
        persist()
        run(Accrual.flushCommands(main: nil, sides: [side], at: clock()))
    }

    /// Change a running side project's percentage: close the current interval at
    /// the old percent, reopen at the new one.
    public func setPercent(_ id: UUID, percent: Double) {
        guard percent > 0, let index = sideProjects.firstIndex(where: { $0.id == id }) else { return }
        let now = clock()
        let closing = sideProjects[index]
        sideProjects[index].percent = percent
        sideProjects[index].intervalStart = now
        persist()
        run(Accrual.flushCommands(main: nil, sides: [closing], at: now))
    }

    // MARK: - Live display (no writes)

    public func mainElapsed(asOf t: Date) -> TimeInterval {
        guard let main else { return 0 }
        return max(0, t.timeIntervalSince(main.start))
    }

    public func sideAccrued(_ side: SideProject, asOf t: Date) -> TimeInterval {
        max(0, t.timeIntervalSince(side.intervalStart)) * side.percent
    }

    // MARK: - Two-way sync with watson's running frame (`state` file)

    /// Reconcile Conan's session with watson's `state` file so a terminal
    /// `watson start` / `watson stop` is reflected here. Runs on the heartbeat and
    /// whenever the popover opens. Reads a tiny file synchronously on the main actor.
    public func reconcile() {
        guard let watson else { return }
        let external = try? watson.runningFrame()
        switch (main, external) {
        case (nil, nil):
            return
        case (nil, .some(let frame)):
            adopt(frame)
        case (.some(let current), .some(let frame)):
            guard !matches(frame, current) else { return }   // already in sync
            // Terminal stopped `current` and started `frame` between polls.
            flushSidesForExternalStop(current, defaultStop: clock())
            adopt(frame)
        case (.some(let current), nil):
            // Terminal `watson stop`: watson already wrote the main frame.
            flushSidesForExternalStop(current, defaultStop: clock())
        }
    }

    /// Take over a frame started in the terminal. The main frame is still open, so
    /// nothing is written and watson's state is left in place (kept in sync).
    private func adopt(_ frame: WatsonRunningFrame) {
        main = MainSession(project: frame.project, start: frame.start, tags: frame.tags, wasAdopted: true)
        persist()
    }

    /// watson closed the main frame itself (`watson stop`). Flush only the side
    /// projects — writing the main frame here would double-count it — pinned to the
    /// stop time watson recorded when we can find it.
    private func flushSidesForExternalStop(_ main: MainSession, defaultStop: Date) {
        lastSetup = SessionSetup(main: main, sides: sideProjects)   // resumable like any other stop
        let stop = externalStop(for: main) ?? defaultStop
        let sides = sideProjects
        self.main = nil
        self.sideProjects = []
        persist()
        run(Accrual.flushCommands(main: nil, sides: sides, at: stop))
        refreshReport()
    }

    private func externalStop(for main: MainSession) -> Date? {
        guard let watson else { return nil }
        return try? watson.stopTime(project: main.project, startEpoch: Int(main.start.timeIntervalSince1970))
    }

    private func currentRunningFrame() -> WatsonRunningFrame? {
        guard let watson else { return nil }
        return try? watson.runningFrame()
    }

    /// Same project and same start second (compare int epochs to dodge float drift).
    private func matches(_ frame: WatsonRunningFrame, _ session: MainSession) -> Bool {
        frame.project == session.project
            && Int(frame.start.timeIntervalSince1970) == Int(session.start.timeIntervalSince1970)
    }

    private func syncRunningFrame(_ session: MainSession) {
        guard let watson else { return }
        do {
            try watson.setRunningFrame(
                WatsonRunningFrame(project: session.project, start: session.start, tags: session.tags)
            )
        } catch {
            lastError = "watson state write failed: \(error)"
        }
    }

    private func dropRunningFrame() {
        guard let watson else { return }
        do { try watson.clearRunningFrame() }
        catch { lastError = "watson state clear failed: \(error)" }
    }

    // MARK: - watson reads (off the main thread, published when ready)

    public func refreshReport() {
        guard let watson else { return }
        Task.detached { [weak self] in
            let report = try? watson.reportDay()
            await self?.setReport(report)
        }
    }

    public func refreshProjects() {
        guard let watson else { return }
        Task.detached { [weak self] in
            let names = (try? watson.projects()) ?? []
            let frames = (try? watson.recentLog()) ?? []
            await self?.setProjects(names, combos: RecentCombos.from(frames))
        }
    }

    private func setReport(_ report: WatsonReport?) { todayReport = report }
    private func setProjects(_ names: [String], combos: [ProjectTags]) {
        projects = names
        recentCombos = combos
    }
    private func setError(_ message: String) { lastError = message }

    // MARK: - watson writes (serialized inside the client)

    private func run(_ commands: [WatsonAddCommand]) {
        guard let watson, !commands.isEmpty else { return }
        Task.detached { [weak self] in
            for command in commands {
                do { try watson.add(command) }
                catch { await self?.setError("watson add failed: \(error)") }
            }
            await self?.refreshReport()
        }
    }

    // MARK: - Persistence + crash recovery

    public nonisolated static func defaultStateURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Conan/state.json")
    }

    private func persist() {
        let state = PersistedState(main: main, sideProjects: sideProjects, lastSeen: clock(), lastSetup: lastSetup)
        do {
            try FileManager.default.createDirectory(
                at: stateURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .secondsSince1970
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(state).write(to: stateURL, options: .atomic)
        } catch {
            lastError = "persist failed: \(error)"
        }
    }

    private func loadState() -> PersistedState? {
        guard let data = try? Data(contentsOf: stateURL) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return try? decoder.decode(PersistedState.self, from: data)
    }

    /// Reconcile any session open at the last quit/crash against watson's current
    /// running frame. The frame in watson's `state` file is the tie-breaker for who
    /// already closed the main interval, so we never double-count it:
    ///  - watson frame matches ours → we crashed mid-session: close at the last
    ///    heartbeat (never count downtime) and drop the baton.
    ///  - watson idle → `watson stop` ran while we were down: it wrote the main
    ///    frame, so flush side projects only.
    ///  - watson frame differs → stopped + restarted while down: flush old sides,
    ///    adopt the new frame.
    ///  - no prior session but watson frame present → adopt it.
    private func recoverOnLaunch() {
        let state = loadState()
        let recoveredMain = state?.main
        let recoveredSides = state?.sideProjects ?? []
        let lastSeen = state?.lastSeen ?? clock()
        let external = currentRunningFrame()

        lastSetup = state?.lastSetup
        // An interrupted setup supersedes any older snapshot, so "Resume all"
        // restores what was actually running when the session ended.
        if let recovered = recoveredMain {
            lastSetup = SessionSetup(main: recovered, sides: recoveredSides)
        }

        switch (recoveredMain, external) {
        case (nil, nil):
            return
        case (nil, .some(let frame)):
            adopt(frame)
        case (.some(let recovered), .some(let frame)) where matches(frame, recovered):
            dropRunningFrame()
            persist()   // main is still nil here → persists idle
            run(Accrual.flushCommands(main: recovered, sides: recoveredSides, at: lastSeen))
        case (.some(let recovered), .some(let frame)):
            let stop = externalStop(for: recovered) ?? lastSeen
            run(Accrual.flushCommands(main: nil, sides: recoveredSides, at: stop))
            adopt(frame)
        case (.some(let recovered), nil):
            let stop = externalStop(for: recovered) ?? lastSeen
            persist()
            run(Accrual.flushCommands(main: nil, sides: recoveredSides, at: stop))
        }
    }

    private func startHeartbeat() {
        heartbeat = Timer.scheduledTimer(withTimeInterval: Self.heartbeatInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.reconcile()   // catch terminal watson start/stop within a heartbeat
                if self.isRunning { self.persist() }
                self.checkIdleReminder()
            }
        }
    }

    /// Fire a reminder if the user has been active at the Mac for a while with no
    /// project tracked (opt-in via the "remind me when not tracking" setting).
    private func checkIdleReminder() {
        let enabled = UserDefaults.standard.bool(forKey: Self.remindWhenIdleDefaultsKey)
        let idle = enabled ? SystemActivity.idleSeconds() : 0
        if idleReminder.tick(now: clock(), idleSeconds: idle, isTracking: isRunning, enabled: enabled) {
            Notifier.notifyNotTracking()
        }
    }
}
