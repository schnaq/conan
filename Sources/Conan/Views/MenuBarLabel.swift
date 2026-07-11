import SwiftUI
import ConanCore

/// The menu-bar item itself: a live elapsed timer when running, otherwise the
/// timer glyph.
struct MenuBarLabel: View {
    @EnvironmentObject private var store: SessionStore
    @EnvironmentObject private var ticker: Ticker

    var body: some View {
        if store.isRunning {
            Text(TimeFormat.clock(store.mainElapsed(asOf: ticker.now)))
                .monospacedDigit()
        } else {
            Image(systemName: "timer")
        }
    }
}
