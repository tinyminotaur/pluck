# Architecture

Twang is a SwiftPM package with three targets:

| Target | What it holds |
| --- | --- |
| `TwangCore` | Pure logic with no AppKit: gesture math, every style's physics simulation, pack format and formula language, presenter math, spectrum analysis. Fully unit tested. |
| `Twang` | The app: event listening, overlay window, rendering, settings, permissions, packs on disk. |
| `TwangTests` | Tests for `TwangCore` (and the pack importer's safety checks). |

## Life of a gesture

1. `Input/` (`ChordEngine`) watches the trigger with a **listen-only** global monitor. Twang never installs an event tap and never posts mouse or keyboard events. `Esc` cancels, `⌃⌥⌘P` quits, and a 12 s idle failsafe ends a stuck gesture.
2. `TwangSession` owns one gesture: it resolves context (the sample actions, or real ones when enabled), shows the overlay and feeds pointer positions to it.
3. `OverlayController` hosts `MetaballView`, a full-screen click-through view. It steps the active style at display rate and draws it.
4. On release the style's `releaseBehavior` (spring, ease or stay) decides how it recoils. The system cursor is never moved on release.

## Styles

Every style is a simulation in `TwangCore` plus a renderer in the app target, tied together by one of two small protocols in `Overlay/Sprites/StyleRunners.swift`:

- `VectorRunner`: sprite styles drawn with pooled Core Animation layers (`Overlay/Sprites/`). Community packs run through the same protocol (`PackRunner`).
- `ShapeRunner`: styles drawn as glass shapes by one Metal shader (`Overlay/Glass/`).
- Liquid is the original metaball renderer and lives in `Overlay/Liquid/`.

`VectorRunners.make(style)` and `ShapeRunners.make(style)` are the only places that know which class belongs to which style, so `MetaballView` has no per-style code. **To add a style:** write a sim in `TwangCore`, a layers class (or shape sim), add a case to `AnimationStyle`, register it in the factory, add a preset in `PresetLibrary`, and add a test. `Twang --render-styles` renders every style to PNGs and `Twang --style-perf` measures frame cost.

## Settings

`TwangConfig` is the single observable settings object, backed by `UserDefaults`. Presets (`FeelPreset`) bundle a style with its tuning. Packs add presets at runtime through `PresetRegistry`.

## Community packs

A pack is a folder with a `pack.json` that describes layers drawn from a small, safe formula language (`PackExpression`). There is no scripting and no file or network access from a pack. `PackLibrary` watches the packs folder, imports `.twangpack` zips with strict checks (no path escapes, symlinks, executables or oversized files) and can fetch an https library whose entries are verified by SHA-256. See [PACKS.md](PACKS.md).

## Privacy and permissions

See [PRIVACY.md](PRIVACY.md). In short: Accessibility is required, Screen Recording only for the optional audio-reactive equalizer, no telemetry, and the network is touched only when you press a button to fetch a pack library.
