import Foundation
import ServiceManagement

/// "Start at login" backed by `SMAppService` (macOS 13+). Registers the bundled
/// app itself as a login item.
@MainActor
public enum LoginItem {
    public static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// Register/unregister the app as a login item. Returns the resulting state,
    /// or throws if the operation failed (e.g. app not in a launchable location).
    @discardableResult
    public static func setEnabled(_ enabled: Bool) throws -> Bool {
        let service = SMAppService.mainApp
        if enabled {
            if service.status != .enabled { try service.register() }
        } else {
            if service.status == .enabled { try service.unregister() }
        }
        return service.status == .enabled
    }
}
