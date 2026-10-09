# Pluck

A playful pointer gesture for macOS. Hold a trigger, stretch a shape from where you are to where you point, and let go.
The shape can be a blob of liquid obsidian, a crystal, a kite on a string, a laser pointer, a lasso, an anime energy beam,
or one of 40+ other animations, and anyone can add more.

It lives in the menu bar and only draws over your screen: it listens to your mouse, keyboard and trackpad but never
blocks or sends any of them, so it can't get in your way.

> **Status: first public preview (0.1).** The gesture, looks and animation library are solid; the optional "real actions"
> (copy, share, tile windows) are a beta and off by default.

## What you can do

- **Stretch things.** Hold ⌥ (or Hyper, or rest three fingers, or hold both mouse buttons), move, and let go.
  Whatever you pick follows your cursor anywhere on screen, and drains or fills with real mass as you pull.
- **Choose a look.** 40+ styles in Settings > Looks: liquid blobs, ferrofluid, crystals, tug of war, paper planes,
  fireworks of anime beams (charge, aim, fire), a marquee and lasso for "selecting" things, a laser pointer, spotlight and
  highlighter for presenting, and more. Each has colour themes.
- **Presenter mode.** Hold, then drag out in one of 4 or 8 directions to pick a visual (lasso up, train down...).
  Drag a little further and it comes to life between the two points. Let go to finish.
- **Add your own.** Animations are small JSON "packs" with safe formulas, no code. Settings > Library has a template,
  hot-reload, and an online library. See [docs/PACKS.md](docs/PACKS.md).

## Install

Download the latest `Pluck.zip` from [Releases](../../releases), unzip, and drag **Pluck.app** to Applications.
macOS 14 (Sonoma) or later. On first launch, grant **Accessibility** when asked (that is the only required permission).
Until releases are notarized, right-click the app and choose *Open* the first time.

Or build it yourself:

```bash
git clone https://github.com/tinyminotaur/pluck && cd pluck
swift build && swift test            # the logic is unit-tested
./scripts/build.sh && open build/Pluck.app
```

`scripts/build.sh` signs with a stable local identity so macOS remembers the Accessibility grant between rebuilds
(it creates one the first time). To make a distributable zip or dmg, see [docs/RELEASING.md](docs/RELEASING.md).

## Triggers

| Trigger | How |
|---|---|
| Hold ⌥ or Hyper (no click) | Hold the modifier (⌥ needs the pointer still for ~250 ms), move, release the modifier |
| Three fingers (optional) | Rest three fingers on the trackpad without moving, then drag; lift to finish |
| Two-button chord | Hold one mouse button, press the other, stretch, release |
| Press-and-hold (optional) | ⌥ + press and hold without moving, then drag |

**Esc** cancels. **⌃⌥⌘P** quits Pluck. A gesture also ends after 12 seconds without movement.
If the pointer ever feels stuck: menu bar > **Reset Pointer / Gesture**.

## Privacy and safety

- No telemetry, no analytics, no accounts. Nothing is sent anywhere unless you press a button (refresh the online
  library, install a pack), and then only over HTTPS with a checksum.
- Pluck does not read your clipboard, files or windows unless you switch on "real actions (beta)".
- Community packs are data, not code: they cannot run programs, read files or use the network.
- The optional audio-reactive Equalizer asks for Screen Recording to hear system audio; only 24 level numbers are used.

Details: [docs/PRIVACY.md](docs/PRIVACY.md) and [SECURITY.md](SECURITY.md).

## Project layout

- `Sources/PluckCore`: pure, tested logic (gesture math, physics models, pack format and formulas, themes and presets)
- `Sources/Pluck`: the app (input, overlay and rendering, Settings, pack library)
- `docs/`: [architecture](docs/ARCHITECTURE.md), [packs](docs/PACKS.md), [testing](docs/TESTING.md), [releasing](docs/RELEASING.md), design research
- `packs/`: example and community animation packs

Contributions are welcome, especially animation packs: see [CONTRIBUTING.md](CONTRIBUTING.md).

## Headless tools

For development, with no input, cursor or permissions needed:

```bash
Pluck --render-styles out.png         # contact sheet of the styles (PLUCK_STYLES=a,b filters)
Pluck --render-preview out.png        # the standard liquid look grid
Pluck --style-perf                    # per-frame cost of every sprite style
Pluck --sim-report                    # liquid physics extent and draw cost
Pluck --validate-pack <folder>        # check a community pack
Pluck --install-pack <file.pluckpack> # install a pack with the app's safety checks
```

## Licence

Apache License 2.0. See [LICENSE](LICENSE) and [NOTICE](NOTICE). Made by [Tiny Minotaur](https://tinyminotaur.co).
