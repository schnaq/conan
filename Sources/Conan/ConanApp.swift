import SwiftUI
import ConanCore

@main
struct ConanApp: App {
    @StateObject private var store: SessionStore
    @StateObject private var ticker = Ticker()
    @StateObject private var updater = UpdaterController()

    init() {
        // Self-contained: reads/writes watson's data files directly, so no
        // `watson` binary install is required (but stays compatible with one).
        let watson = FileWatsonClient()
        _store = StateObject(wrappedValue: SessionStore(watson: watson))
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarContentView()
                .environmentObject(store)
                .environmentObject(ticker)
                .environmentObject(updater)
        } label: {
            MenuBarLabel()
                .environmentObject(store)
                .environmentObject(ticker)
        }
        .menuBarExtraStyle(.window)
    }
}
