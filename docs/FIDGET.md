# Pluck as a desktop fidget toy

Goal: something you can play with one-handed in a meeting — silent, discreet, instantly
re-graspable, and deeply satisfying — while still being a real gesture launcher.

## Principles

1. **Silent first.** No sound by default. Delight comes from motion, light and (on a trackpad) haptics.
2. **Zero-latency head, laggy body.** The head is glued to the cursor; all lag, slosh and whip live in the body. That gap *is* the toy.
3. **Always alive.** Held still, the blob breathes. It should never look like a frozen sprite.
4. **Reward the release.** The snap-back overshoot is the payoff of every pull — the "thwip".
5. **Instantly re-grabbable.** A new chord during a recoil cuts it and starts a fresh blob. No cooldown.
6. **Liquid → obsidian under tension.** Facets are subtle at rest and sharpen as the tether stretches; releasing flashes them.

## Implemented (Feel Lab knobs under "Fidget feel")

| Feel | Where | Knob |
|---|---|---|
| Spring snap-back with overshoot on release, then melt-away | `MetaballView.beginRecoil` / `integrateRecoil` | Release bounce |
| Facets crystallize with stretch; flash on release | `drawOptical` (`facetEff`) | Crystallize with stretch, Facets |
| Idle breathing while held still | slosh `breathing` term | Idle breathing |
| Slack in the tether so it bows, sags and whips | `slack` in `stepPhysics` | Whip response |
| Trackpad haptic: tick when a direction latches, ratchet click every ~56 pt of stretch | `PluckSession.pointerMoved`, `Haptics` | Trackpad haptic ticks |
| Sharp, snap-on glints that sweep across facets as the pointer moves the light | shader `glint` | Facets |
| Cursor returns immediately on release; overlay stops eating clicks | `PluckSession.finishVisual`, `OverlayController.commit` | — |
| Re-grab during a recoil | `PluckSession.begin` | — |

Physics is a fixed 240 Hz step (≤4 substeps per frame) so the feel is identical on 60/120 Hz displays.

| Direction labels (pills with SF Symbol glyphs), armed pop, slice arc, cancel ring, commit confirmation flash | `MetaballView.drawCompass`, `updateCompassUI`, `LabelLayout` | — |
| Stir: circling the pin builds slosh + glint energy that outlasts the motion | `stir` in `MetaballView` | Slosh amount |
| Menu-bar quick toggles: Meeting Mode, Trackpad Haptics | `AppDelegate` | — |
| macOS CI: build, tests, Metal compile, real-Metal preview render uploaded as an artifact | `.github/workflows/ci.yml`, `Pluck --render-preview` | — |

## Ideas not built yet (ordered by delight per effort)

- **Flick-to-fling:** release at speed and the head overshoots far past the pin before recoiling (momentum is already kept at 50%; expose it as a knob and add a faint speed-streak in the shader).
- **Quiet "tink" sound** (opt-in, off by default): a soft glassy tick on facet glints / direction latch, volume tied to stretch speed. Respect system mute and Focus.
- **Pin-pull "pop":** pull past a maximum stretch and the tether snaps into 2–3 droplets that merge back (pinch-off; Rayleigh–Plateau limit ≈ length/diameter π).
- **Meeting mode:** smaller (`restRadius` ~36), dimmer tint, no label bloom, auto-cancel after a few seconds idle — less conspicuous on a shared screen. Excluded automatically while screen sharing (SCStream/`sharingType`).
- **Surface rewards:** a rare shimmer variant (golden/rainbow sheen obsidian) on long sessions or streaks of clean directional flicks.
- **Gentle idle prompt:** when Pluck has not been used for a while, a barely visible ripple near the menu bar icon invites a poke.
- **Left-hand / button swap** and keyboard-only fidget (hold ⌥, mouse move) for people who can't chord.

## Safety notes

Escape cancel and the ⌃⌥⌘P panic quit are unchanged. The old 20 s hard cap (a testing aid) is now an
**idle** failsafe: the gesture ends after 12 s without movement, with a 30 min absolute cap, so a
held toy never strands the cursor.

## Also implemented

- **Fling momentum** knob: how much release speed carries the head past the pin.
- **Meeting mode** toggle: 65 % size, 80 % opacity.
- `RecoilSpring` (PluckCore) holds the snap-back math with unit tests.

## Open question: trackpads

The trigger is a two-mouse-button chord, which a MacBook trackpad cannot produce. Candidate
trackpad triggers (pending a decision): modifier + click-and-hold (listen-only, but the click
also reaches the app underneath), force-click drag, or an active event tap to swallow the
click (reintroduces the lock-up risk the listen-only design avoids).
