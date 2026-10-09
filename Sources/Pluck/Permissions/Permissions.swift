import ApplicationServices
import AppKit

/// Pluck needs exactly one permission: Accessibility, to notice the trigger and draw over other apps.
/// (Screen Recording is requested separately, and only if the audio-reactive Equalizer is switched on.)
/// It never automates System Settings and never sends keystrokes or clicks.
enum Permissions {
    static var accessibilityTrusted: Bool { AXIsProcessTrusted() }

    static func requestAccessibility() {
        NSApp.activate(ignoringOtherApps: true)
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(opts)
    }

    static func openAccessibilitySettings() {
        let urls = [
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Accessibility",
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility",
        ]
        for s in urls {
            if let url = URL(string: s), NSWorkspace.shared.open(url) { return }
        }
    }
}
