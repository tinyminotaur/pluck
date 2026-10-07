import ApplicationServices
import AppKit
import Foundation
import IOKit.hid

enum Permissions {
    static var accessibilityTrusted: Bool {
        AXIsProcessTrusted()
    }

    static func requestAccessibility() {
        NSApp.activate(ignoringOtherApps: true)
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(opts)
    }

    /// Informational only — we do NOT automate System Settings or inject keystrokes.
    static var inputMonitoringTrusted: Bool {
        IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted
    }

    /// Opens the Input Monitoring pane and shows manual steps.
    /// Never sends keystrokes, never clicks UI, never installs event taps.
    @MainActor
    static func showInputMonitoringHelp() {
        openInputMonitoringSettings()
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(appPath, forType: .string)
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: appPath)])

        let alert = NSAlert()
        alert.messageText = "Add Pluck manually (safe)"
        alert.informativeText = """
        Pluck will not control System Settings for you (that locked input before).

        1. In Input Monitoring, click +
        2. Choose Pluck.app (Finder has it selected; path is on the clipboard)
        3. Turn Pluck On

        Feel Lab works without this — Accessibility alone is enough for testing the blob.
        """
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    /// Kept for call sites — redirects to safe help. Does not call IOHIDRequestAccess
    /// in a loop or drive Settings UI.
    @discardableResult
    @MainActor
    static func requestInputMonitoring() -> Bool {
        if inputMonitoringTrusted { return true }
        showInputMonitoringHelp()
        return inputMonitoringTrusted
    }

    static var appPath: String { Bundle.main.bundlePath }

    static var bundleIdentifier: String {
        Bundle.main.bundleIdentifier ?? "(no bundle id)"
    }

    static func openAccessibilitySettings() {
        openPrivacyPane("Privacy_Accessibility")
    }

    static func openInputMonitoringSettings() {
        openPrivacyPane("Privacy_ListenEvent")
    }

    private static func openPrivacyPane(_ anchor: String) {
        let urls = [
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?\(anchor)",
            "x-apple.systempreferences:com.apple.preference.security?\(anchor)",
        ]
        for s in urls {
            if let url = URL(string: s), NSWorkspace.shared.open(url) { return }
        }
    }
}
