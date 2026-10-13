import Observation
import ServiceManagement

/// Wraps the app's Login Item registration (`SMAppService.mainApp`).
@MainActor @Observable
final class LaunchAtLogin {
    private(set) var isEnabled = false
    /// Registered, but the user still has to allow it in System Settings.
    private(set) var needsApproval = false
    private(set) var error: String?

    init() {
        refresh()
    }

    /// Re-reads the status; it can change in System Settings behind our back.
    func refresh() {
        let status = SMAppService.mainApp.status
        isEnabled = status == .enabled || status == .requiresApproval
        needsApproval = status == .requiresApproval
    }

    func set(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
        refresh()
    }

    func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
