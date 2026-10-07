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
- Input Monitoring (two-button chord via `CGEventTap`)

## Build & run

```bash
cd pluck
swift build
swift run
# or package an .app:
./scripts/build.sh
open build/Pluck.app
```

On first launch, Pluck asks for the two permissions. Then **hold one mouse button and press the other**, stretch, release.

If the pointer ever feels stuck: menu bar drop → **Stop Listening** or **Quit Pluck** (or `pkill Pluck`).

## Reduced Motion

System Reduce Motion replaces the metaball with a plain cross and labels. The same angles and dead zone still apply.

## Development

- `PluckCore` — gesture math, compass model, exclude list (unit-tested)
- `Pluck` — event tap, overlay, Accessibility context, actions, settings

## License

Apache License 2.0. See [LICENSE](LICENSE).
