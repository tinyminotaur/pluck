# Testing

## Automated

```bash
swift test          # ~150 tests: gesture math, physics, every style's simulation, pack format, formulas, presenter logic
```

CI (`.github/workflows/ci.yml`) also compiles the Metal shader, validates the example packs and renders a preview.

Headless rendering checks (no input or permissions):

```bash
swift build -c release
.build/release/Twang --render-styles /tmp/styles.png      # eyeball every style; TWANG_STYLES=tugofwar,rainbow filters
TWANG_PREVIEW_DIR=left .build/release/Twang --render-styles /tmp/left.png   # pull leftward (also up, down, diag)
.build/release/Twang --style-perf                          # per-frame cost; keep every style well under 1 ms
```

## Manual checklist (about 10 minutes)

Twang only listens, so it cannot lock your keyboard or mouse. Safety nets: **Esc** cancels, **⌃⌥⌘P** quits, an idle gesture ends
after 12 s, and menu bar > *Reset Pointer / Gesture* restores the cursor.

1. First launch: Accessibility prompt appears; after granting, Settings opens once and the menu-bar drop shows "Listening".
2. Hold ⌥ (pointer still ~250 ms), move, release: the shape rises, follows the cursor anywhere, and ends on release.
3. The system cursor hides during a gesture and reappears *exactly where it was* on release (it must never jump).
4. Three-finger trigger (Settings > Trigger): rest three fingers, drag, lift.
5. Pull to the screen edge and beyond the middle of the screen: no length cap, no snap back until release.
6. Esc cancels; ⌃⌥⌘P quits; 12 s of stillness ends a gesture.
7. Presenter mode: choose directions, drag out, the choice locks until release, the visual comes alive, the name fades.
8. Pull in every direction (left, up, down): no character or object appears upside down.
9. Settings > Library: template creates a pack; edit it and watch it hot-reload; break it and see the error.
10. Menu bar > Launch at Login toggles; Settings > General > Ignore these apps stops Twang in that app.
11. With "real actions" off, nothing reads the clipboard (Activity Monitor shows no pasteboard polling in `Twang`).
12. Reduce Motion (System Settings): no springs or wobble.
