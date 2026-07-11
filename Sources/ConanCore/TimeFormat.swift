import Foundation

public enum TimeFormat {
    /// Zero-padded "hh:mm" (e.g. "00:05", "01:23") for a live clock display.
    /// Seconds are floored away so a minute only appears once fully elapsed.
    public static func clock(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds))
        let hours = total / 3600, minutes = (total % 3600) / 60
        return String(format: "%02d:%02d", hours, minutes)
    }

    /// Compact "1h 23m" / "23m" / "45s" for the report.
    public static func human(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded()))
        let hours = total / 3600, minutes = (total % 3600) / 60, secs = total % 60
        if hours > 0 { return "\(hours)h \(minutes)m" }
        if minutes > 0 { return "\(minutes)m" }
        return "\(secs)s"
    }
}
