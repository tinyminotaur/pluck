import AppKit

// `Pluck --snapshot <dir>` renders scripted gestures to PNGs and exits. No input, no cursor, no permissions.
if let i = CommandLine.arguments.firstIndex(of: "--snapshot") {
    let dir = CommandLine.arguments.count > i + 1 ? CommandLine.arguments[i + 1] : "snapshots"
    let code = MainActor.assumeIsolated { Snapshot.run(outputDir: dir) }
    exit(code)
}

// Menu-bar accessory: no Dock icon when packaged with LSUIElement; policy covers `swift run`.
MainActor.assumeIsolated {
    CursorGuard.installExitHooks()
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}
