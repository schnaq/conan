import Foundation
import Combine

/// Single source of truth for the running session. Conan owns all timing and
/// writes completed frames to watson when intervals close — it never calls
/// `watson start`/`stop` and never touches watson's `state`.
@MainActor
public final class SessionStore: ObservableObject {
    @Published public private(set) var main: MainSession?
    @Published public private(set) var sideProjects: [SideProject] = []
    @Published public private(set) var todayReport: WatsonReport?
    @Published public private(set) var projects: [String] = []
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

    public func startMain(project: String) {
        let name = project.trimmingCharacters(in: .whitespacesAndNewlines)
        guard main == nil, !name.isEmpty else { return }
        main = MainSession(project: name, start: clock())
        persist()
    }

    /// Stop the main project and every side project at once.
    public func stopAll() {
        guard main != nil else { return }
        let commands = Accrual.flushCommands(main: main, sides: sideProjects, at: clock())
        main = nil
        sideProjects = []
        persist()
        run(commands)
    }

    // MARK: - Side projects

    public func addSide(project: String, percent: Double) {
        let name = project.trimmingCharacters(in: .whitespacesAndNewlines)
        guard main != nil, !name.isEmpty, percent > 0 else { return }
        sideProjects.append(SideProject(name: name, percent: percent, intervalStart: clock()))
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
            await self?.setProjects(names)
        }
    }

    private func setReport(_ report: WatsonReport?) { todayReport = report }
    private func setProjects(_ names: [String]) { projects = names }
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
        let state = PersistedState(main: main, sideProjects: sideProjects, lastSeen: clock())
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

    /// If a session was open at the last quit/crash, flush all open intervals up
    /// to the last heartbeat, then start idle — never lose tracked time up to the
    /// heartbeat, never over-count a long gap.
    private func recoverOnLaunch() {
        guard let state = loadState(), state.main != nil else { return }
        let commands = Accrual.flushCommands(
            main: state.main,
            sides: state.sideProjects,
            at: state.lastSeen
        )
        main = nil
        sideProjects = []
        persist()
        run(commands)
    }

    private func startHeartbeat() {
        heartbeat = Timer.scheduledTimer(withTimeInterval: Self.heartbeatInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
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
