import AppKit
import TwangCore

// `Twang --render-preview out.png`: headless Metal render for CI / design review, then exit.
if let i = CommandLine.arguments.firstIndex(of: "--render-preview") {
    let path = CommandLine.arguments.indices.contains(i + 1) ? CommandLine.arguments[i + 1] : "preview.png"
    let code = MainActor.assumeIsolated { PreviewRender.run(outputPath: path) }
    exit(code)
}

// `Twang --render-compass out.png`: the real view with its integrated action labels (headless), then exit.
if let i = CommandLine.arguments.firstIndex(of: "--render-compass") {
    let path = CommandLine.arguments.indices.contains(i + 1) ? CommandLine.arguments[i + 1] : "compass.png"
    exit(MainActor.assumeIsolated { PreviewRender.runCompass(outputPath: path) })
}

// `Twang --live-smoke out.png`: the real Metal-layer view in a brief click-through window; prints frame pacing.
if let i = CommandLine.arguments.firstIndex(of: "--live-smoke") {
    let path = CommandLine.arguments.indices.contains(i + 1) ? CommandLine.arguments[i + 1] : "live.png"
    let style = CommandLine.arguments.indices.contains(i + 2) ? CommandLine.arguments[i + 2] : "liquid"
    MainActor.assumeIsolated { LiveSmoke.run(outputPath: path, style: style) }
}

// `Twang --render-style-commit out.png`: the real view committing in each non-liquid style (headless), then exit.
if let i = CommandLine.arguments.firstIndex(of: "--render-style-commit") {
    let path = CommandLine.arguments.indices.contains(i + 1) ? CommandLine.arguments[i + 1] : "style-commit.png"
    exit(MainActor.assumeIsolated { PreviewRender.runStyleCommit(outputPath: path) })
}

// `Twang --validate-pack <folder|pack.json>`: check a community pack and print any problems (exit code 1 if invalid).
if let i = CommandLine.arguments.firstIndex(of: "--validate-pack") {
    let arg = CommandLine.arguments.indices.contains(i + 1) ? CommandLine.arguments[i + 1] : "."
    var url = URL(fileURLWithPath: arg)
    if url.pathExtension != "json" { url = url.appendingPathComponent("pack.json") }
    guard let data = try? Data(contentsOf: url) else { print("error: cannot read \(url.path)"); exit(2) }
    let (manifest, decodeIssues) = PackDecoder.decode(data)
    guard let manifest else { decodeIssues.forEach { print("error: \($0)") }; exit(1) }
    let (_, issues) = PackProgram.compile(manifest)
    if issues.isEmpty { print("ok: \(manifest.name) (\(manifest.id) \(manifest.version ?? "")) is a valid pack with \(manifest.layers.count) layers"); exit(0) }
    issues.forEach { print("error: \($0)") }
    exit(1)
}

// `Twang --install-pack <file.twangpack|folder>`: install a community pack headlessly (same checks as the app), then exit.
if let i = CommandLine.arguments.firstIndex(of: "--install-pack") {
    let arg = CommandLine.arguments.indices.contains(i + 1) ? CommandLine.arguments[i + 1] : ""
    let code: Int32 = MainActor.assumeIsolated {
        do { let p = try PackLibrary.shared.install(from: URL(fileURLWithPath: arg)); print("installed: \(p.name)"); return 0 }
        catch { print("refused: \(error.localizedDescription)"); return 1 }
    }
    exit(code)
}

// `Twang --style-perf`: per-frame cost of every sprite style, then exit.
if CommandLine.arguments.contains("--style-perf") {
    exit(MainActor.assumeIsolated { PreviewRender.runPerf() })
}

// `Twang --render-styles out.png`: the ferrofluid and crystal styles (headless), then exit.
if let i = CommandLine.arguments.firstIndex(of: "--render-styles") {
    let path = CommandLine.arguments.indices.contains(i + 1) ? CommandLine.arguments[i + 1] : "styles.png"
    exit(MainActor.assumeIsolated { PreviewRender.runStyles(outputPath: path) })
}

// `Twang --render-pinch out.png`: the commit pinch-off over time (headless), then exit.
if let i = CommandLine.arguments.firstIndex(of: "--render-pinch") {
    let path = CommandLine.arguments.indices.contains(i + 1) ? CommandLine.arguments[i + 1] : "pinch.png"
    exit(MainActor.assumeIsolated { PreviewRender.runPinch(outputPath: path) })
}

// `Twang --render-themes out.png`: one row per theme (headless Metal), then exit.
if let i = CommandLine.arguments.firstIndex(of: "--render-themes") {
    let path = CommandLine.arguments.indices.contains(i + 1) ? CommandLine.arguments[i + 1] : "themes.png"
    let all = ThemeLibrary.all + [ThemeLibrary.random(seed: 2026)]
    exit(MainActor.assumeIsolated { PreviewRender.run(outputPath: path, themes: all) })
}

// `Twang --sim-report`: headless physics diagnostic, then exit.
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
