# Pluck: handoff notes (Oct 7, 2026)

macOS menu-bar utility: hold both mouse buttons, stretch a liquid drop toward Keep (N) / Go (E) / Give (S) / Ask (W), release to act. Swift 5.9 package, macOS 14+. The app is in **Feel Lab mode** (listen-only, gesture and liquid only; no real actions).

## Hard safety rules (the owner was locked out of the cursor once)
- Never add a `CGEventTap`, never synthesize mouse/keyboard events, never disassociate mouse and cursor.
- Hide/show the system cursor **only** through `Sources/Pluck/Safety/CursorGuard.swift` (one balanced hide per gesture, background watchdog, exit hooks). Never call `NSCursor.hide()` per frame.
- The overlay panel must keep `ignoresMouseEvents = true`.
- Do **not** launch the live app or simulate the chord in an automated session. Use `.build/debug/Pluck --snapshot <dir>` (offscreen render to PNGs; touches no input or cursor).

## What changed this session
- Coordinates standardized to AppKit **y-up**. The old code treated north as negative-y, so pulling up registered as South.
- `PluckCore/GestureMath.swift`: `GestureTracker` (dead zone with hysteresis 22 in / 14 out, angular hysteresis, unavailable roles capture nothing, release commits what you saw), gain curve `virtualLength`.
- `PluckCore/LiquidTether.swift`: pure fixed-240Hz simulation (head spring, chase-spring neck, slosh, role lobes that fuse into the head on capture, commit droplet, cancel recoil). 24 unit tests pass.
- `Overlay/BlobRenderer.swift`: Metal capsule-SDF renderer (dark glass, iridescent rim, contact shadow), presented from a bbox-sized `CAMetalLayer` (no CPU readback). `LiquidView.swift` drives it from `CADisplayLink` and draws labels. `OverlayController.swift` hosts the click-through panel.
- `ChordEngine`: no queue hops, no move throttle, per-frame hardware button check (`buttonsStillHeld`), 12 s failsafe.
- `FeelLabConfig`: new knobs under the `pluck.feel2.` prefix; `FeelGuideView` updated.

## Verified / not verified
- Verified: core tests (`swift test`), app builds, offscreen snapshots look right for pull, long stretch, captured-lobe fusion, commit, cancel.
- **Not verified:** the live gesture on a real display; label placement in the live view (the snapshot compositor had a row-flip bug that was patched but the result was not re-inspected); `scripts/build.sh` packaging; real (non-Feel) mode.
- Not committed to tests: `swift test` was last run before the app-side rewrite.

## Next steps
1. Re-run `swift build`, `swift test`, and `.build/debug/Pluck --snapshot snapshots`; inspect `snapshots/*.png` (labels should read right-side-up: Keep above the pin, Give below).
2. Known visual nits: faceted highlight on the thin neck and a wedge highlight on the pin during whips; chosen lobe at commit is larger than the droplet.
3. Owner tests the live feel locally via `./scripts/build.sh && open build/Pluck.app` (needs the local "Pluck Dev" signing identity; keys are gitignored).
4. Later: real mode needs async context resolution (`ContextResolver` is `@MainActor`; it is only deferred past the first frame today), the event tap with withhold-and-replay, multi-display support, and a README/TEST.md rewrite (README still describes the old CGEventTap design).
