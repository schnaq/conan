import SwiftUI
import ConanCore

/// The menu-bar item itself: a live elapsed timer when running (or a static
/// recording glyph when the clock is hidden), otherwise the timer glyph.
struct MenuBarLabel: View {
    @EnvironmentObject private var store: SessionStore
    @EnvironmentObject private var ticker: Ticker
    @AppStorage(SessionStore.hideMenuBarClockDefaultsKey) private var hideClock = false

    var body: some View {
        if store.isRunning {
            if hideClock {
                Image(systemName: "record.circle")
            } else {
                Text(TimeFormat.clock(store.mainElapsed(asOf: ticker.now)))
                    .monospacedDigit()
            }
        } else {
            Image(systemName: "timer")
        }
    }
}
