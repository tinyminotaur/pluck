import AppKit
import TwangCore
import SwiftUI

/// The menu-bar app: owns the status item, the listening session and the first-run flow.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem?
    private let session = TwangSession()
    private var listening = false
    private var permissionWatcher: Timer?
    private static let onboardedKey = "twang.onboarded"

    func applicationDidBecomeActive(_ notification: Notification) { AudioSpectrumController.shared.refresh() }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        // Compile the Metal shader now, not on the first gesture (that compile was a visible first-frame hitch).
        _ = ObsidianBlobMetal.shared
        setupStatusItem()
        startPermissionWatcher()
        AudioSpectrumController.shared.bind()
        PackLibrary.shared.start()
        StylePrewarm.shared.start()

        NotificationCenter.default.addObserver(forName: .twangResetHard, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.session.engine.resetHard() }
        }
        NotificationCenter.default.addObserver(forName: .twangRealActionsChanged, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.session.applyRealActions() }
        }

        let firstRun = !UserDefaults.standard.bool(forKey: Self.onboardedKey)
        if Permissions.accessibilityTrusted {
            startListening()
            // A menu-bar app should not throw a window at you on every launch: only the very first time.
            if firstRun { SettingsWindowController.shared.show() }
        } else {
            SetupWindowController.shared.show { [weak self] in
                self?.startListening()
                SettingsWindowController.shared.show()
            }
        }
        UserDefaults.standard.set(true, forKey: Self.onboardedKey)
    }

    func applicationWillTerminate(_ notification: Notification) {
        permissionWatcher?.invalidate()
        stopListening()
    }

    // MARK: Menu bar

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.image = NSImage(systemSymbolName: "drop.fill", accessibilityDescription: "Twang")
            button.toolTip = "Twang"
        }
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        statusItem = item
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let cfg = TwangConfig.shared

        if !Permissions.accessibilityTrusted {
            menu.addItem(disabled("Needs the Accessibility permission"))
            menu.addItem(action("Set Up Accessibility…", #selector(openSetup)))
        } else {
            menu.addItem(disabled(listening ? "Listening" : "Not listening"))
        }
        menu.addItem(.separator())

        let settings = action("Settings…", #selector(showSettings), key: ",")
        menu.addItem(settings)
        menu.addItem(action(listening ? "Stop Listening" : "Start Listening", #selector(toggleListening)))
        menu.addItem(.separator())

        // Looks: each style, with its looks underneath when it has several.
        let looks = NSMenu()
        for st in AnimationStyle.allCases {
            let presets = PresetLibrary.presets(for: st)
            guard !presets.isEmpty else { continue }
            if presets.count == 1 {
                looks.addItem(presetItem(presets[0], title: st.name))
            } else {
                let sub = NSMenu()
                for p in presets { sub.addItem(presetItem(p, title: p.name)) }
                let parent = NSMenuItem(title: st.name, action: nil, keyEquivalent: "")
                parent.submenu = sub
                parent.state = cfg.style == st ? .on : .off
                looks.addItem(parent)
            }
        }
        let looksItem = NSMenuItem(title: "Looks", action: nil, keyEquivalent: "")
        looksItem.submenu = looks
        menu.addItem(looksItem)

        let themes = NSMenu()
        for t in ThemeLibrary.all {
            let item = NSMenuItem(title: t.name, action: #selector(selectTheme(_:)), keyEquivalent: "")
            item.target = self; item.representedObject = t.id; item.toolTip = t.tagline
            item.state = cfg.themeID == t.id ? .on : .off
            themes.addItem(item)
        }
        themes.addItem(.separator())
        let surprise = NSMenuItem(title: "Surprise Me", action: #selector(surpriseTheme), keyEquivalent: "")
        surprise.target = self
        surprise.state = cfg.themeID == "custom" ? .on : .off
        themes.addItem(surprise)
        let themeItem = NSMenuItem(title: "Colours", action: nil, keyEquivalent: "")
        themeItem.submenu = themes
        menu.addItem(themeItem)

        menu.addItem(.separator())
        menu.addItem(toggle("Presenter Mode", #selector(togglePresenter), on: cfg.presenterMode))
        menu.addItem(toggle("Meeting Mode (smaller, dimmer)", #selector(toggleMeeting), on: cfg.meetingMode))
        menu.addItem(toggle("Trackpad Haptics", #selector(toggleHaptics), on: cfg.hapticsEnabled))
        menu.addItem(toggle("Soft Sounds", #selector(toggleSounds), on: cfg.soundEnabled))
        menu.addItem(toggle("Launch at Login", #selector(toggleLogin), on: LoginItem.isEnabled))

        menu.addItem(.separator())
        menu.addItem(action("Reset Pointer / Gesture", #selector(resetHard)))
        menu.addItem(action("Quit Twang", #selector(quit), key: "q"))
    }

    private func presetItem(_ p: FeelPreset, title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: #selector(selectPreset(_:)), keyEquivalent: "")
        item.target = self; item.representedObject = p.id; item.toolTip = p.tagline
        item.state = TwangConfig.shared.presetID == p.id ? .on : .off
        return item
    }

    private func action(_ title: String, _ sel: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: sel, keyEquivalent: key)
        item.target = self
        return item
    }

    private func toggle(_ title: String, _ sel: Selector, on: Bool) -> NSMenuItem {
        let item = action(title, sel)
        item.state = on ? .on : .off
        return item
    }

    private func disabled(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    // MARK: Actions

    @objc private func showSettings() { SettingsWindowController.shared.show() }
    @objc private func openSetup() { SetupWindowController.shared.show { [weak self] in self?.startListening() } }
    @objc private func toggleListening() { if listening { stopListening() } else { startListening() } }
    @objc private func toggleMeeting() { TwangConfig.shared.meetingMode.toggle() }
    @objc private func togglePresenter() { TwangConfig.shared.interactionModeID = TwangConfig.shared.presenterMode ? "actions" : "presenter" }
    @objc private func toggleSounds() { TwangConfig.shared.soundEnabled.toggle() }
    @objc private func toggleHaptics() { TwangConfig.shared.hapticsEnabled.toggle() }
    @objc private func surpriseTheme() { TwangConfig.shared.surpriseMe() }
    @objc private func resetHard() { session.engine.resetHard() }

    @objc private func toggleLogin() {
        if let problem = LoginItem.set(!LoginItem.isEnabled) {
            let alert = NSAlert()
            alert.messageText = "Couldn't change the login item"
            alert.informativeText = problem
            alert.runModal()
        }
    }

    @objc private func selectPreset(_ sender: NSMenuItem) {
        if let id = sender.representedObject as? String, let p = PresetLibrary.preset(id: id) { TwangConfig.shared.apply(preset: p) }
    }

    @objc private func selectTheme(_ sender: NSMenuItem) {
        if let id = sender.representedObject as? String, let t = ThemeLibrary.theme(id: id) { TwangConfig.shared.apply(theme: t) }
    }

    @objc private func quit() {
        stopListening()
        NSApp.terminate(nil)
    }

    // MARK: Listening

    private func startListening() {
        guard Permissions.accessibilityTrusted else { openSetup(); return }
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
}
