import AppKit

// `Pluck --render-preview out.png`: headless Metal render for CI / design review, then exit.
if let i = CommandLine.arguments.firstIndex(of: "--render-preview") {
    let path = CommandLine.arguments.indices.contains(i + 1) ? CommandLine.arguments[i + 1] : "preview.png"
    let code = MainActor.assumeIsolated { PreviewRender.run(outputPath: path) }
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
