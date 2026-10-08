# Pluck

A macOS menu-bar utility: hold both mouse buttons, stretch a liquid drop toward a direction, release to act.

- **Keep** (north) — copy / keep what you’re holding  
- **Go** (east) — the forward action  
- **Give** (south) — share / hand off  
- **West** (ask) — look up / get info  

What you grabbed (selection, link, file, clipboard, or window chrome) chooses the labels. Release near the pin to cancel.

## Requirements

- macOS 14+
- Accessibility (read under-pointer context, run actions)
- That's it: the two-button chord is detected with listen-only `NSEvent` monitors. There is **no** `CGEventTap` and **no** Input Monitoring permission, so Pluck cannot swallow or delay your input. See [TEST.md](TEST.md) for the safety guarantees.

## Build & run

```bash
cd pluck
swift build
swift run
# or package an .app:
./scripts/build.sh
open build/Pluck.app
```

On first launch, Pluck asks for Accessibility. Then **hold one mouse button and press the other**, stretch, release.

If the pointer ever feels stuck: **Escape**, stop moving for 12 s, menu bar drop → **Reset Pointer** / **Quit Pluck**, panic quit **⌃⌥⌘P**, or `pkill Pluck`.

## Reduced Motion

System Reduce Motion replaces the metaball with a plain cross and labels. The same angles and dead zone still apply.

## Feel

Pluck is meant to be a little bit of a fidget toy: a glossy obsidian-liquid blob with springy snap-back, facets that sharpen as you stretch, trackpad haptic detents, and a Meeting Mode that keeps it small and quiet. Tune everything live in the Feel Lab window; design notes live in [docs/FIDGET.md](docs/FIDGET.md) and the research behind it in `reports/`.

## Development

- `PluckCore` — gesture math, compass model, exclude list (unit-tested)
- `Pluck` — chord monitors, overlay (Metal blob + direction labels), Accessibility context, actions, settings
- `scripts/preview` — WebGL port of the shader for checking the look without a Mac
- CI (`.github/workflows/ci.yml`) builds and tests on macOS

## License

Apache License 2.0. See [LICENSE](LICENSE).
