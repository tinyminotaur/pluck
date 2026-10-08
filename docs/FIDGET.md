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

## Ideas not built yet (ordered by delight per effort)

- **Flick-to-fling:** release at speed and the head overshoots far past the pin before recoiling (momentum is already kept at 50%; expose it as a knob and add a faint speed-streak in the shader).
- **Orbit / whirl:** circling the pointer builds slosh energy that keeps sloshing after you stop; a "stir" meter that makes facets glint faster.
- **Quiet "tink" sound** (opt-in, off by default): a soft glassy tick on facet glints / direction latch, volume tied to stretch speed. Respect system mute and Focus.
- **Pin-pull "pop":** pull past a maximum stretch and the tether snaps into 2–3 droplets that merge back (pinch-off; Rayleigh–Plateau limit ≈ length/diameter π).
- **Meeting mode:** smaller (`restRadius` ~36), dimmer tint, no label bloom, auto-cancel after a few seconds idle — less conspicuous on a shared screen. Excluded automatically while screen sharing (SCStream/`sharingType`).
- **Surface rewards:** a rare shimmer variant (golden/rainbow sheen obsidian) on long sessions or streaks of clean directional flicks.
- **Gentle idle prompt:** when Pluck has not been used for a while, a barely visible ripple near the menu bar icon invites a poke.
- **Left-hand / button swap** and keyboard-only fidget (hold ⌥, mouse move) for people who can't chord.

## Safety notes

The 20 s failsafe, Escape cancel and ⌃⌥⌘P panic quit are unchanged. For a toy that is held for a long time the failsafe will probably want to become *idle-based* (cancel after N seconds without movement) rather than a hard cap — that is a safety trade-off to decide deliberately.
