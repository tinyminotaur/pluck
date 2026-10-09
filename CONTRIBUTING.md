# Contributing to Pluck

Thanks for helping. Pluck is a small macOS app, and the easiest ways to contribute are **animation packs** (no Swift
needed) and **bug reports**. Code contributions are welcome too.

## Make an animation pack (no code)

Packs are JSON files with tiny formulas. See [docs/PACKS.md](docs/PACKS.md). In the app: Settings > Library >
*New pack from template*, edit, and it hot-reloads. Check it with `Pluck --validate-pack <folder>`. To share one, open a
"Pack submission" issue or a pull request adding a folder under `packs/community/`.

## Report a bug

Open an issue with the template. Please include your macOS version, the trigger you used (hold ⌥, three-finger, ...),
and what you expected. If the pointer ever felt stuck, say so, and attach `~/Library/Logs/Pluck/gesture.log` if you had
the diagnostic log switched on (Settings > Help).

## Code

Requirements: macOS 14+, Swift 5.9+ (Xcode 15+ or the Swift toolchain).

```bash
swift build && swift test          # logic is in PluckCore and is unit-tested
./scripts/build.sh                 # builds build/Pluck.app signed with a stable local identity
```

Layout:

- `Sources/PluckCore`: pure, tested logic (gesture math, physics models, pack format and formulas, themes, presets). No AppKit.
- `Sources/Pluck`: the app (input, overlay and rendering, Settings UI, pack library).
- `docs/ARCHITECTURE.md`: how the pieces fit, and the rules that keep the pointer safe.

Ground rules (these protect people's computers, so PRs that break them will not be merged):

1. **Listen-only input.** Pluck never installs an event tap and never synthesizes mouse or keyboard events. Escape, the
   panic quit (⌃⌥⌘P) and the idle failsafe must keep working.
2. **No code from packs.** Packs stay declarative. New capabilities become new layer types or formula functions with
   limits, never scripting.
3. **Nothing leaves the Mac unless the person asks.** Network calls only happen on a button press; no telemetry.
4. **Tests for logic.** New behaviour in `PluckCore` comes with tests. Rendering code is checked with the headless tools
   (`Pluck --render-styles out.png`, `--style-perf`).
5. **Keep it light.** Aim for well under a millisecond per frame for a style; `Pluck --style-perf` reports it.

Style: follow the surrounding code; comments explain *why*. Keep PRs focused; describe what you checked.

## Licence

By contributing you agree your contribution is licensed under the Apache License 2.0 (see [LICENSE](LICENSE)).
Animation packs you submit to the community library must carry an open licence stated in their `pack.json`.
