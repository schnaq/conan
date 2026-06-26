import SwiftUI
import ConanCore

@main
struct ConanApp: App {
    @StateObject private var store: SessionStore
    @StateObject private var ticker = Ticker()

    init() {
        let watson = ProcessWatsonClient()
        _store = StateObject(wrappedValue: SessionStore(watson: watson))
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarContentView()
                .environmentObject(store)
                .environmentObject(ticker)
        } label: {
            MenuBarLabel()
                .environmentObject(store)
                .environmentObject(ticker)
        }
        .menuBarExtraStyle(.window)
    }
}
