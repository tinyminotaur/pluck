import AppKit

// Menu-bar accessory: no Dock icon when packaged with LSUIElement; policy covers `swift run`.
MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}
