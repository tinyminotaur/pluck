# Pluck

A macOS menu-bar gesture utility: grab a blob of liquid obsidian, stretch it toward a direction, let go to act.
Four directions, one gesture, no settings to open first.

- **Keep** (up): copy or keep what you are holding
- **Go** (right): the forward action
- **Give** (down): share or hand off
- **Ask** (left): look up or get info

Nothing is drawn at rest except the liquid itself. Move into a direction and that action's glyph and name appears
inside the head of the liquid. Release to commit (the head pinches off as a droplet and flies to the action);
release near the pin to cancel.

> Status: **Feel Lab**. The gesture, physics and look are being tuned, so actions do not run yet. See
> [docs/HANDOFF.md](docs/HANDOFF.md) for the current state and [docs/ACTIONS.md](docs/ACTIONS.md) for what each
> direction will do.

## Triggers

Pluck is **listen-only** (no event tap, it never synthesizes input), so it can never lock your mouse or keyboard.

| Trigger | How |
|---|---|
| Hold ⌥ or Hyper (no click) | Hold the modifier (⌥ needs the pointer still for ~250 ms), move to stretch, release the modifier to commit |
| Three fingers (experimental, off by default) | Rest three fingers on the trackpad without moving, then drag; lift to commit |
| Two-button chord | Hold one mouse button, press the other, stretch, release |
| Press-and-hold (off by default) | ⌥ + press and hold without moving, then drag |

Escape cancels. **⌃⌥⌘P** quits Pluck. A gesture also ends after 12 s without movement.

## Animation styles

Beyond the liquid, two completely different styles respond to your movement (pick one in the Feel Lab guide or the
menu bar under **Animation Style**, or choose a preset that sets it):

- **Ferrofluid**: mirror-black chrome that bristles into a fan of spikes aimed at the cursor (the magnet), a
  smaller mass at the cursor that bristles back, and iron filings strung along curved field lines. The fan swings
  around with lag and overshoot as you move.
- **Crystal**: a crystal rosette grows a faceted needle toward the cursor; the distance you travel seeds branches,
  which sprout sub-branches, so the formation keeps evolving while you hold. Commit shatters it; cancel retracts it.

## Looks and feels

The Feel Lab window (menu bar drop → Show Feel Lab Guide) has 14 feel presets (physics and colours together) and
12 colour themes with gradient palettes, plus a "Surprise me" random palette. The menu bar has the same under
**Feel Preset** and **Colour Theme**. Hundreds of live knobs are underneath, saved between launches.

## Requirements

macOS 14+. Accessibility (to listen for the trigger).

## Build and run

```bash
swift build && swift test
./scripts/build.sh && open build/Pluck.app     # signed with a stable local identity so Accessibility sticks
```

Headless tools (no input, no cursor, no permissions):

```bash
.build/release/Pluck --render-compass out.png   # the live view with its action label
.build/release/Pluck --render-pinch out.png     # the commit pinch-off over time
.build/release/Pluck --render-themes out.png    # every theme
.build/release/Pluck --render-styles out.png    # ferrofluid and crystal
.build/release/Pluck --render-style-commit out.png   # their commit animations
.build/release/Pluck --live-smoke out.png ferro     # real display link: frame pacing + capture (liquid|ferro|crystal)
.build/release/Pluck --render-preview out.png   # the standard look grid
.build/release/Pluck --sim-report               # physics extent and draw cost
```

## Layout

- `Sources/PluckCore`: pure, tested logic: gesture math, the dumbbell shape model, themes and presets, triggers
- `Sources/Pluck`: the app: Metal renderer, physics view, input engine, Feel Lab UI, cursor guard
- `docs/`: handoff notes, the action schema, design research

If the pointer ever feels stuck: menu bar drop → **Reset Pointer / Gesture**, or `pkill -x Pluck`.
The cursor guard also restores it automatically, and `~/Library/Logs/Pluck/gesture.log` records why gestures end.

## License

Apache License 2.0. See [LICENSE](LICENSE).
