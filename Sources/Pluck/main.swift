import AppKit
import PluckCore

// `Pluck --render-preview out.png`: headless Metal render for CI / design review, then exit.
if let i = CommandLine.arguments.firstIndex(of: "--render-preview") {
    let path = CommandLine.arguments.indices.contains(i + 1) ? CommandLine.arguments[i + 1] : "preview.png"
    let code = MainActor.assumeIsolated { PreviewRender.run(outputPath: path) }
    exit(code)
}

// `Pluck --render-compass out.png`: the real view with its integrated action labels (headless), then exit.
if let i = CommandLine.arguments.firstIndex(of: "--render-compass") {
    let path = CommandLine.arguments.indices.contains(i + 1) ? CommandLine.arguments[i + 1] : "compass.png"
    exit(MainActor.assumeIsolated { PreviewRender.runCompass(outputPath: path) })
}

// `Pluck --live-smoke out.png`: the real Metal-layer view in a brief click-through window; prints frame pacing.
if let i = CommandLine.arguments.firstIndex(of: "--live-smoke") {
    let path = CommandLine.arguments.indices.contains(i + 1) ? CommandLine.arguments[i + 1] : "live.png"
    MainActor.assumeIsolated { LiveSmoke.run(outputPath: path) }
}

// `Pluck --render-pinch out.png`: the commit pinch-off over time (headless), then exit.
if let i = CommandLine.arguments.firstIndex(of: "--render-pinch") {
    let path = CommandLine.arguments.indices.contains(i + 1) ? CommandLine.arguments[i + 1] : "pinch.png"
    exit(MainActor.assumeIsolated { PreviewRender.runPinch(outputPath: path) })
}

// `Pluck --render-themes out.png`: one row per theme (headless Metal), then exit.
if let i = CommandLine.arguments.firstIndex(of: "--render-themes") {
    let path = CommandLine.arguments.indices.contains(i + 1) ? CommandLine.arguments[i + 1] : "themes.png"
    let all = ThemeLibrary.all + [ThemeLibrary.random(seed: 2026)]
    exit(MainActor.assumeIsolated { PreviewRender.run(outputPath: path, themes: all) })
}

// `Pluck --sim-report`: headless physics diagnostic, then exit.
if CommandLine.arguments.contains("--sim-report") {
    exit(MainActor.assumeIsolated { SimReport.run() })
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
