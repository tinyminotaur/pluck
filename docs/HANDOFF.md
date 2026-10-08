# Handoff: Pluck feel/UX work (from cloud session to a local Mac agent)

Branch: `claude/confident-mccarthy-btj39d` (no PR open). Latest CI: green (macOS 15: build, 28 tests, Metal compile, real-Metal preview render).

## What Pluck is
macOS 14+ menu-bar gesture utility: hold two mouse buttons (or a trackpad trigger), drag a liquid-obsidian blob toward N/E/S/W, release to act. Currently in **Feel Lab** mode (default on): gesture + visuals only, actions don't run. **Listen-only by design** (NSEvent monitors, no CGEventTap, never synthesize input). Read `TEST.md` and the safety notes before touching `ChordEngine`.

## What was built in the cloud session (all compiled by CI, NOT yet seen running on a real screen)
- **Rendering** (`Sources/Pluck/Overlay/ObsidianBlobMetal.swift`): 2D SDF; tapered round-cone segments for the tether + smooth-union end lobes; pillow-profile height; Fresnel, Beer absorption, Blinn spec; material-space Voronoi facets (domed, chipped silhouette, seams, snap-on glints); IGN dither. Darkened to read as obsidian.
- **Physics** (`MetaballRenderer.swift`): fixed 240 Hz accumulator (<=4 substeps), soft-clamped drive speed, tether slack, idle breathing, "stir" energy when circling, spring snap-back (`PluckCore/RecoilSpring.swift`) with fling momentum, crystallize-with-stretch, latch squash.
- **Direction UI** (`MetaballRenderer.drawCompass`, `PluckCore/LabelLayout.swift`): pills with SF Symbol glyphs, labels gated (~0.22 s or when slow; suppressed on fast flicks), armed pop spring, slice arc, dashed cancel ring, commit confirmation flash, edge-safe label clamp (slices never move).
- **Gesture math** (`PluckCore/GestureMath.swift`): dead zone 24/16 pt hysteresis, angular hysteresis, release uses captured role. **Fixed a bug: North/South were inverted** (AppKit y-up vs y-down); flipped once in `PluckSession.screenSpace`.
- **Triggers** (`Input/ChordEngine.swift`): mouse chord (unchanged); trackpad **modifier + press-and-hold** (`PluckCore/HoldArm.swift`, default ⌥, 220 ms); **three-finger** (experimental, off by default; `Input/MultitouchMonitor.swift`, private MultitouchSupport via dlsym).
- **Safety**: Escape, ⌃⌥⌘P panic quit, idle failsafe 12 s (30 min hard cap), overlay stops eating clicks on release, per-frame `NSCursor.hide()` removed.
- **Feel Lab knobs** (`Feel/FeelLabConfig.swift`, `FeelGuideView.swift`): facets, fidget (bounce, crystallize, idle, fling, meeting mode, haptics), trackpad triggers. Menu bar has Meeting Mode / Haptics toggles.
- **Haptics** (`Feel/Haptics.swift`): trackpad ticks on direction latch and every ~56 pt of stretch.
- **Tooling**: `.github/workflows/ci.yml`; `Pluck --render-preview out.png` (headless real-Metal render + brightness stats); `scripts/preview/` WebGL port of the shader (must be kept in sync by hand).
- **Docs**: `docs/FIDGET.md` (design + ideas), `reports/Obsidian liquid blob design practices.md` (research, with sourced vs opinion tagged), `research_notes/`.

## Verified vs unverified
Verified by CI: compiles, 28 unit tests pass, shader compiles with `xcrun metal`, renders headlessly. Real-Metal preview stats after darkening: meanLum ~0.23-0.26, glints 2.5-8%.
**Not verified by anyone yet (needs a human + a real screen):** everything interactive: feel of the snap-back/bounce/breathing, label timing, haptics, cursor hiding, overlay window behavior across Spaces/full-screen, trackpad ⌥-hold, three-finger.

## First things to do on the Mac
1. `git fetch && git checkout claude/confident-mccarthy-btj39d && git pull`, `swift build && swift test`, then `./scripts/build.sh && open build/Pluck.app` (or `swift run`). Grant Accessibility.
2. Walk the checklist in `TEST.md` (items 1-17) and report what is wrong/feels off.
3. Download the `blob-preview` artifact from the latest Actions run (real-Metal render) or run `.build/release/Pluck --render-preview /tmp/p.png` and eyeball it.

## Known issues / suspicious spots
- Overlay renders via offscreen texture + `waitUntilCompleted` + CPU readback + CGImage every frame (`ObsidianBlobMetal.render`). Biggest perf/latency item; plan is a `CAMetalLayer` in a bbox-sized panel (see report action #1). Not done.
- Faint seam at rest where head lobe overlaps pin (visible in previews).
- `GestureMath.lobeDistance` (84) vs `LabelLayout.distance` (92) are separate numbers; `magnetRadius`/`stretchGain` are legacy and partly unused by the renderer.
- Dead params: `PluckSession` `bloomDelay` etc. only gate `bloom`; label timing now lives in `MetaballView.updateCompassUI`.
- Cursor hiding relies on `CGDisplayHideCursor` + `NSCursor.hide` from an `.accessory` app; may not hide reliably in all contexts. Verify, esp. on full-screen Spaces.
- Trackpad ⌥-hold is listen-only: the underlying app also receives the click/drag. Check for annoying side effects (Finder copy-drag, column select).
- Three-finger path untested on hardware; assumes Three Finger Drag is enabled and system 3-finger gestures are off.
- Reduce Motion path draws the flat fallback; labels have no springs there. Reduce Transparency / Increase Contrast not handled yet.
- WebGL port in `scripts/preview/index.html` can drift from the Metal source.

## Next ideas (ordered)
CAMetalLayer rewrite; tune feel numbers from real use; flick-commit + earlier arming on fast stable flicks; droplet pinch-off on overstretch; optional quiet "tink" sound; accessibility (Reduce Transparency/Increase Contrast, keyboard alternative); real actions out of Feel Lab; per-app exclusion UI.

## Ground rules for the agent
Keep it listen-only (no event tap, no synthesized input). Commit small, push, and check CI (`gh run list`/Actions). Do not open a PR unless asked. Don't rewrite history on this branch.

## Update (local session): what changed since the cloud session
- **Cursor:** all hide/show goes through `Safety/CursorGuard` (one balanced hide, background watchdog, signal/atexit hooks, private `SetsCursorInBackground` opt-in so hiding works for a background app).
- **Gotcha fixed:** polling modifier state (HID or `NSEvent.modifierFlags`) reports *released* for a held Hyper/remapped key; it ended every modifier gesture at the 1 s tick. Modifier state now comes only from `flagsChanged` events. `gesture.log` made this findable.
- **Triggers:** hold-⌥ (pointer still) or Hyper, move, release the modifier to commit (`PluckCore/ModifierTrigger`); three-finger rest-to-arm with scroll/landing filters (`TouchEligibility`) and a flicker-proof release (`TouchReleaseDebounce`); click-based hold trigger is off by default. Modifier state uses the HID state (`CGEventSource.flagsState`), not `NSEvent.modifierFlags`.
- **Edge nudge:** the pin (and real cursor) is moved 72 pt inside the screen so every direction is reachable.
- **Look:** one fixed environment (no light swing, no cursor-aligned texture), organic seeded lump clusters + water warp, wet-glass shading with dome normals, strand drawn as a Catmull-Rom spline with soft-unioned segments.
- **Physics:** head is a magnet-pulled spring mass (`MagnetPull`), gravity droop + pooling, always-on wander; tether meanders.
- **Reach:** the head can reach anywhere on screen (`GestureMath.reachHead`, screen-aware, no cap; knob "Reach gain").
- **Themes and presets:** `PluckCore/LiquidTheme.swift` (8 themes + random "Surprise"), presets in the same file; picker in the Feel Lab guide and menu-bar submenus. Palette is a 3-stop gradient (A,B,C) with drift, iridescence, colour `fill` and `chrome`.
- **Integrated label:** nothing shows at rest. Once a direction latches, that one action's glyph + name appears *inside the head of the liquid* (the head swells into a bud: a field circle with an `emphasis` value, text drawn with a screen blend tinted by the theme). Quiet during fast flicks; on commit the chosen one swells. (An earlier version showed four permanent buds around the pin; rejected as ugly.)
- **Diagnostics:** `~/Library/Logs/Pluck/gesture.log` (why gestures end), `Pluck --sim-report`, `--render-preview`, `--render-themes`, `--render-compass` (all headless, no input).
- **Not verified live:** feel of the magnet/gravity physics, bud labels in the live view, cursor hiding with the private opt-in, three-finger on hardware.
