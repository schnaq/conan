import Foundation
import Combine
import ConanCore

/// Connects Conan to an Adafruit MacroPad running the schnaqqi firmware
/// (schnaq/macropad). Off unless enabled; while on, it looks for the device every
/// few seconds, and talks to it once a port says hello.
@MainActor
public final class MacropadBridge: ObservableObject {
    public enum Status { case off, searching, connected }

    /// UserDefaults key for the "MacroPad" setting (off by default).
    public static let enabledDefaultsKey = "conan.macropad.enabled"

    @Published public private(set) var status: Status = .off

    private static let searchInterval: TimeInterval = 3
    private static let projectRefreshTicks = 600 // re-rank project keys every 10 min

    private let store: SessionStore
    private let controller: PadController
    private var port: SerialPort?
    private var probes: [SerialPort] = []
    private var buffer = LineBuffer()
    private var searchTimer: Timer?
    private var tickTimer: Timer?
    private var ticks = 0
    private var storeChanges: AnyCancellable?
    private var sendScheduled = false

    public init(store: SessionStore) {
        self.store = store
        controller = PadController(store: store, defaults: .standard, clock: { Date() }, idleSeconds: SystemActivity.idleSeconds)
    }

    public func setEnabled(_ enabled: Bool) {
        enabled ? start() : stop()
    }

    private func start() {
        guard status == .off else { return }
        status = .searching
        search()
        searchTimer = Timer.scheduledTimer(withTimeInterval: Self.searchInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.search() }
        }
    }

    private func stop() {
        searchTimer?.invalidate()
        searchTimer = nil
        closeProbes()
        disconnect()
        status = .off
    }

    // MARK: - Finding the device

    /// Opens every Adafruit port and keeps the one that says hello (the data port;
    /// the REPL console never does). Unanswered probes are closed on the next round.
    private func search() {
        guard port == nil else { return }
        closeProbes()
        for path in DeviceFinder.candidates() {
            guard let probe = SerialPort(path: path) else { continue }
            var probeBuffer = LineBuffer()
            probe.onData = { [weak self, weak probe] data in
                MainActor.assumeIsolated {
                    guard let self, let probe else { return }
                    if probeBuffer.append(data).contains(where: { PadEvent.decode($0) == .hello }) { self.connect(probe) }
                }
            }
            probes.append(probe)
        }
    }

    private func closeProbes() {
        let open = probes
        probes = []
        open.forEach { $0.close() }
    }

    private func connect(_ probe: SerialPort) {
        probes.removeAll { $0 === probe }
        closeProbes()
        port = probe
        buffer = LineBuffer()
        controller.reset() // a key release may have been lost while disconnected
        status = .connected
        probe.onData = { [weak self] data in
            MainActor.assumeIsolated { self?.received(data) }
        }
        probe.onClose = { [weak self] in
            MainActor.assumeIsolated { self?.disconnect() }
        }
        store.refreshProjects()
        store.refreshReport()
        storeChanges = store.objectWillChange.sink { [weak self] _ in self?.scheduleSend() }
        tickTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        send()
    }

    private func disconnect() {
        tickTimer?.invalidate()
        tickTimer = nil
        storeChanges = nil
        let old = port
        port = nil
        old?.onClose = nil
        old?.close()
        if status == .connected { status = .searching }
    }

    // MARK: - Talking to the device

    private func received(_ data: Data) {
        for line in buffer.append(data) {
            guard let event = PadEvent.decode(line) else { continue }
            controller.handle(event)
        }
        send()
    }

    private func tick() {
        ticks += 1
        if ticks % Self.projectRefreshTicks == 0 { store.refreshProjects() }
        send()
    }

    /// Coalesces bursts of store changes into one send after the change has landed.
    private func scheduleSend() {
        guard !sendScheduled else { return }
        sendScheduled = true
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                self?.sendScheduled = false
                self?.send()
            }
        }
    }

    private func send() {
        port?.write(controller.state().encodedLine())
    }
}
