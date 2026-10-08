import AppKit
import PluckCore
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem?
    private let session = PluckSession()
    private var listening = false
    private var permissionWatcher: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        setupStatusItem()
        startPermissionWatcher()

        NotificationCenter.default.addObserver(
            forName: .pluckResetHard,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.session.engine.resetHard() }
        }

        FeelLab.enabled = true
        FeelGuideController.shared.show()

        if Permissions.accessibilityTrusted {
            startListening()
        } else {
            SetupWindowController.shared.show { [weak self] in
                self?.startListening()
                FeelGuideController.shared.show()
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        permissionWatcher?.invalidate()
        stopListening()
    }

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.image = NSImage(systemSymbolName: "drop.fill", accessibilityDescription: "Pluck")
            button.toolTip = "Pluck Feel Lab — safe listen-only"
        }
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        statusItem = item
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        menu.addItem(disabled("Mode: Feel Lab · listen-only (safe)"))
        menu.addItem(disabled("Accessibility: \(Permissions.accessibilityTrusted ? "On" : "Off")"))

        menu.addItem(.separator())

        let guide = NSMenuItem(title: "Show Feel Lab Guide", action: #selector(showGuide), keyEquivalent: "l")
        guide.target = self
        menu.addItem(guide)

        if !Permissions.accessibilityTrusted {
            let setup = NSMenuItem(title: "Set Up Accessibility…", action: #selector(openSetup), keyEquivalent: "")
            setup.target = self
            menu.addItem(setup)
        }

        let listen = NSMenuItem(
            title: listening ? "Stop Listening" : "Start Listening",
            action: #selector(toggleListening),
            keyEquivalent: ""
        )
        listen.target = self
        menu.addItem(listen)

        menu.addItem(.separator())
        let meeting = NSMenuItem(title: "Meeting Mode (small, dim)", action: #selector(toggleMeeting), keyEquivalent: "m")
        meeting.target = self
        meeting.state = FeelLabConfig.shared.meetingMode ? .on : .off
        menu.addItem(meeting)
        let haptics = NSMenuItem(title: "Trackpad Haptics", action: #selector(toggleHaptics), keyEquivalent: "")
        haptics.target = self
        haptics.state = FeelLabConfig.shared.hapticsEnabled ? .on : .off
        menu.addItem(haptics)
        menu.addItem(.separator())

        let reset = NSMenuItem(title: "Reset Pointer / Gesture", action: #selector(resetHard), keyEquivalent: "")
        reset.target = self
        menu.addItem(reset)

        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit Pluck", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
    }

    private func disabled(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    @objc private func showGuide() { FeelGuideController.shared.show() }

    @objc private func openSetup() {
        SetupWindowController.shared.show { [weak self] in
            self?.startListening()
        }
    }

    @objc private func toggleListening() {
        if listening { stopListening() } else { startListening() }
    }

    @objc private func toggleMeeting() {
        FeelLabConfig.shared.meetingMode.toggle()
    }

    @objc private func toggleHaptics() {
        FeelLabConfig.shared.hapticsEnabled.toggle()
    }

    @objc private func resetHard() {
        session.engine.resetHard()
    }

    private func startListening() {
        guard Permissions.accessibilityTrusted else {
            openSetup()
            return
        }
        session.startListening()
        listening = true
    }

    private func stopListening() {
        session.stopListening()
        listening = false
    }

    private func startPermissionWatcher() {
        var lastAX = Permissions.accessibilityTrusted
        permissionWatcher = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                let ax = Permissions.accessibilityTrusted
                if ax && !lastAX { self.startListening() }
                if !ax && lastAX { self.stopListening() }
                lastAX = ax
            }
        }
    }

    @objc private func quit() {
        stopListening()
        NSApp.terminate(nil)
    }
}
