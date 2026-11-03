import Foundation
import ConanCore

/// Turns MacroPad input into SessionStore actions and the store's state into what
/// the MacroPad shows. Hardware keys: 0 STOP, 1 NEBEN, 2 HEUTE, 3–11 project keys P1–P9.
@MainActor
final class PadController {
    static let slotsKey = "conan.macropad.slots"
    static let sidePercent = 0.5
    // Calibration knobs: seconds.
    static let listTimeout: TimeInterval = 3
    static let gridTimeout: TimeInterval = 5
    static let noteTimeout: TimeInterval = 2
    static let blinkFor: TimeInterval = 1

    private enum LED {
        static let off = "000000", function = "101010", main = "00ff00", side = "ff8800", alert = "ff0000"
    }

    private let store: SessionStore
    private let defaults: UserDefaults
    private let clock: () -> Date
    private let idleSeconds: () -> TimeInterval
    private var moods = MoodTracker()

    private(set) var slots: [String?]
    private var rankedFrom: [String: TimeInterval]?
    private var nebenDown = false
    private var todayDown = false
    private var gridUntil: Date?
    private var list: [ProjectTags] = []
    private var selection = 0
    private var listUntil: Date?
    private var note = ""
    private var noteUntil: Date?
    private var blinkUntil: Date?

    init(store: SessionStore, defaults: UserDefaults, clock: @escaping () -> Date, idleSeconds: @escaping () -> TimeInterval) {
        self.store = store
        self.defaults = defaults
        self.clock = clock
        self.idleSeconds = idleSeconds
        slots = (defaults.stringArray(forKey: Self.slotsKey) ?? []).map { $0.isEmpty ? nil : $0 }
    }

    // MARK: - Input

    func handle(_ event: PadEvent) {
        let now = clock()
        switch event {
        case .hello:
            break
        case .key(let n):
            guard n < slots.count, let project = slots[n] else { return }
            nebenDown ? toggleSide(project, now: now) : startMain(project, now: now)
        case .stop:
            store.stopAll()
            list = []
        case .neben(let down):
            nebenDown = down
        case .today(let down):
            todayDown = down
            if down { gridUntil = now.addingTimeInterval(Self.gridTimeout) }
        case .encoder(let delta):
            if list.isEmpty { list = listOptions(); selection = 0 }
            guard !list.isEmpty else { return }
            selection = min(max(selection + delta, 0), list.count - 1)
            listUntil = now.addingTimeInterval(Self.listTimeout)
        case .press:
            guard listIsOpen(now), list.indices.contains(selection) else { return }
            let combo = list[selection]
            list = []
            if let main = store.main, main.project == combo.project {
                store.retagMain(combo.tags)
            } else {
                startMain(combo.project, tags: combo.tags, now: now)
            }
        }
    }

    private func startMain(_ project: String, tags: [String]? = nil, now: Date) {
        guard store.main?.project != project || tags != nil else { return }
        store.switchMain(project: project, tags: tags ?? lastTags(of: project))
        blinkUntil = now.addingTimeInterval(Self.blinkFor)
    }

    private func toggleSide(_ project: String, now: Date) {
        guard let main = store.main else { return show("erst Hauptprojekt", now: now) }
        guard main.project != project else { return }
        if let side = store.sideProjects.first(where: { $0.name == project }) {
            store.stopSide(side.id)
        } else {
            store.addSide(project: project, percent: Self.sidePercent, tags: lastTags(of: project))
        }
    }

    private func show(_ text: String, now: Date) {
        note = text
        noteUntil = now.addingTimeInterval(Self.noteTimeout)
    }

    private func lastTags(of project: String) -> [String] {
        store.recentCombos.first { $0.project == project }?.tags ?? []
    }

    /// Running: the running project's tag variants; idle: every recent combo.
    private func listOptions() -> [ProjectTags] {
        guard let main = store.main else { return store.recentCombos }
        let own = store.recentCombos.filter { $0.project == main.project }
        return own.isEmpty ? [ProjectTags(project: main.project, tags: main.tags)] : own
    }

    private func listIsOpen(_ now: Date) -> Bool {
        !list.isEmpty && (listUntil.map { now < $0 } ?? false)
    }

    // MARK: - Output

    func state() -> PadState {
        let now = clock()
        refreshSlots()
        if !listIsOpen(now) { list = [] }
        let mood = moods.tick(now: now, idleSeconds: idleSeconds(), isRunning: store.isRunning, startedAt: store.main?.start)

        var state = PadState()
        state.mood = mood.rawValue
        state.leds = leds(for: mood)
        state.fx = blinkUntil.map { now < $0 } == true ? "blink" : (mood == .demand || mood == .alert ? "pulse" : "none")

        if let main = store.main {
            let elapsed = store.mainElapsed(asOf: now)
            state.title = main.project
            state.sub = main.tags.map { "+\($0)" }.joined(separator: " ")
            state.time = Self.hms(elapsed)
            state.note = mood == .sleep
                ? "läuft noch \(TimeFormat.clock(elapsed))"
                : (store.sideProjects.isEmpty ? "" : "+\(store.sideProjects.count) neben")
        } else if mood == .demand || mood == .alert {
            state.note = "nix läuft?!"
        }
        if noteUntil.map({ now < $0 }) == true { state.note = note }

        if !list.isEmpty {
            state.view = "list"
            state.list = list.map(\.display)
            state.sel = selection
        } else if nebenDown || todayDown || gridUntil.map({ now < $0 }) == true {
            state.view = "grid"
            state.grid = slots.map { project in
                project.map { [$0, nebenDown && !todayDown ? "" : TimeFormat.clock(todaySeconds(of: $0, now: now))] }
            }
        }
        return state
    }

    private func leds(for mood: Mood) -> [String] {
        guard mood != .sleep else { return Array(repeating: LED.off, count: 12) }
        let sides = Set(store.sideProjects.map(\.name))
        let projectKeys = slots.map { project -> String in
            guard let project else { return LED.off }
            if project == store.main?.project { return LED.main }
            if sides.contains(project) { return LED.side }
            switch mood {
            case .demand: return LED.side
            case .alert: return LED.alert
            default: return LED.off
            }
        }
        return Array(repeating: LED.function, count: 3) + projectKeys
    }

    /// Today's committed time plus the running main session.
    private func todaySeconds(of project: String, now: Date) -> TimeInterval {
        let committed = store.todayReport?.projects.first { $0.name == project }?.time ?? 0
        return committed + (store.main?.project == project ? store.mainElapsed(asOf: now) : 0)
    }

    /// Re-ranks the key slots whenever Conan's 28-day totals change.
    private func refreshSlots() {
        guard rankedFrom != store.recentTotals else { return }
        rankedFrom = store.recentTotals
        slots = SlotAssigner.assign(previous: slots, totals: store.recentTotals)
        defaults.set(slots.map { $0 ?? "" }, forKey: Self.slotsKey)
    }

    private static func hms(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds))
        return String(format: "%d:%02d:%02d", total / 3600, (total % 3600) / 60, total % 60)
    }
}
