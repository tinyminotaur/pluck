import ServiceManagement

/// Launch at login, via the system's login-item service (shows up in System Settings > General > Login Items).
enum LoginItem {
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    /// Returns an error message if the system refused (for example an unsigned development build).
    @discardableResult
    static func set(_ on: Bool) -> String? {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            return nil
        } catch {
            return error.localizedDescription
        }
    }
}
