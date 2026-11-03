import SwiftUI
import ConanCore
import ConanMacropad

@main
struct ConanApp: App {
    @StateObject private var store: SessionStore
    @StateObject private var ticker = Ticker()
    @StateObject private var updater = UpdaterController()
    @StateObject private var macropad: MacropadBridge

    init() {
        // Self-contained: reads/writes watson's data files directly, so no
        // `watson` binary install is required (but stays compatible with one).
        let watson = FileWatsonClient()
        let store = SessionStore(watson: watson)
        let macropad = MacropadBridge(store: store)
        macropad.setEnabled(UserDefaults.standard.bool(forKey: MacropadBridge.enabledDefaultsKey))
        _store = StateObject(wrappedValue: store)
        _macropad = StateObject(wrappedValue: macropad)
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarContentView()
                .environmentObject(store)
                .environmentObject(ticker)
                .environmentObject(updater)
                .environmentObject(macropad)
        } label: {
            MenuBarLabel()
                .environmentObject(store)
                .environmentObject(ticker)
        }
        .menuBarExtraStyle(.window)
    }
}
