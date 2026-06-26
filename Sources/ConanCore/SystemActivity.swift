import Foundation
import CoreGraphics

/// System-wide user-input idle time (keyboard + mouse), used to tell whether the
/// user is actively at the Mac.
public enum SystemActivity {
    /// Seconds since the most recent user HID input (the minimum across input
    /// event types). ~0 means the user is active right now.
    public static func idleSeconds() -> TimeInterval {
        let inputTypes: [CGEventType] = [
            .keyDown, .flagsChanged,
            .leftMouseDown, .rightMouseDown, .otherMouseDown,
            .mouseMoved, .leftMouseDragged, .rightMouseDragged,
            .scrollWheel,
        ]
        let idles = inputTypes.map {
            CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: $0)
        }
        return idles.min() ?? .greatestFiniteMagnitude
    }
}
