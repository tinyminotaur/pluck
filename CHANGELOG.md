# Changelog

All notable changes. Format based on [Keep a Changelog](https://keepachangelog.com/); versions follow [SemVer](https://semver.org/).

## [Unreleased]

First public preview.

### Security
- Get Info on a file whose name contained quotes could run AppleScript from the name (real actions only). File names are now escaped.
- Pack import now refuses archives that contain symbolic links, and checks the uncompressed size before extracting.
- Pasting a clipboard item no longer sends a synthetic Command-V; it puts the item on the pasteboard and you press Command-V.

### Added
- **Ball of Thread** style: a ball of thread unspools as you stretch and ends in a lasso loop. Let go and the loop is thrown, cinches shut, and the thread winds back into the ball.
- Release tooling: `scripts/package.sh` (universal, optional Developer ID signing and notarization), a tag-triggered release workflow, `scripts/build-library.sh` for pack libraries, and three example packs in `packs/examples`.
- Styles are warmed up off screen at launch so the first gesture has no hitch.
- 40+ animation styles: liquid, ferrofluid, crystal, gravity, anime energy attacks (11 variants with charge-and-fire), selection
  tools (marquee, jelly, freehand lasso), presentation tools (laser pointer, highlighter, spotlight, callout, target lock) and a
  large set of playful scenes.
- Presenter mode: pick a visual by dragging out in 4 or 8 directions.
- Community animation packs: safe JSON plus formulas, hot reload, an online library, and a validator.
- Optional audio-reactive equalizer (system audio, opt-in).
- Per-concept release behaviour (springs only where things are elastic).

### Changed
- The window formerly called "Feel Lab" is now **Settings**.

### Changed
- Internal: every style now runs behind one of two runner protocols; the overlay view has no per-style code.
- Accessibility values are type-checked instead of force-cast, so an odd app cannot crash Pluck.
