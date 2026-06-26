import SwiftUI

/// Publishes the current time once a second so live timers update everywhere
/// (menu-bar label + popover) without each view owning its own timer.
@MainActor
final class Ticker: ObservableObject {
    @Published var now: Date = Date()
    private var timer: Timer?

    init() {
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.now = Date() }
        }
    }
}

enum TimeFormat {
    /// "1:23:45" (with hours) or "23:45" for a live clock display.
    static func clock(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded()))
        let hours = total / 3600, minutes = (total % 3600) / 60, secs = total % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, secs)
            : String(format: "%d:%02d", minutes, secs)
    }

    /// Compact "1h 23m" / "23m" / "45s" for the report.
    static func human(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded()))
        let hours = total / 3600, minutes = (total % 3600) / 60, secs = total % 60
        if hours > 0 { return "\(hours)h \(minutes)m" }
        if minutes > 0 { return "\(minutes)m" }
        return "\(secs)s"
    }
}

struct SectionHeader: View {
    let title: String
    init(_ title: String) { self.title = title }
    var body: some View {
        Text(title.uppercased())
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
            .tracking(0.5)
    }
}

enum AppInfo {
    /// App version from the bundle's Info.plist, e.g. "v0.1.0 (2)".
    /// Falls back to "dev" when running the bare binary (no bundle plist).
    static var version: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        switch (short, build) {
        case let (short?, build?): return "v\(short) (\(build))"
        case let (short?, nil): return "v\(short)"
        default: return "dev"
        }
    }
}
