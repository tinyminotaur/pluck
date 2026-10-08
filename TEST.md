# Pluck Feel Lab: testing

Pluck is **listen-only**: it cannot lock your keyboard or mouse (no event tap, no synthesized input).

## Safety nets

- **Escape** cancels · **⌃⌥⌘P** quits · 12 s without movement ends a gesture (30 min hard cap)
- A background watchdog restores the cursor if the app stalls; menu bar → **Reset Pointer / Gesture**
- `~/Library/Logs/Pluck/gesture.log` records every gesture: trigger, why it ended, how long, how far

## Setup

1. `./scripts/build.sh && open build/Pluck.app` and grant **Accessibility** once.
2. Feel Lab guide window: pick a preset and a theme.

## Triggers (use whichever you have)

- **Hold ⌥** (pointer still ~250 ms) or **Hyper**, move, release the modifier
- **Three fingers** rest, then drag; lift to commit (turn it on in the guide; best with system three-finger drag off)
- **Two-button chord** (if you have a second button)

## Checklist

1. The drop rises over the cursor and the system cursor hides; it returns the instant you release
2. Nothing is drawn around the drop at rest (no labels, no buds)
3. Pull any direction: it keeps stretching all the way to the screen edge; it never snaps back until you release
4. Up is Keep, right is Go, down is Give, left is Ask (check all four)
5. The shape is two matched round masses with a fine filament between (not a head with a tail); no zigzag or kinks
6. The latched direction's glyph and name appear inside the head; fast flicks show no label
7. Release a latched direction: the thread snaps, a droplet carrying the label flies off, a tiny bead trails, the rest rounds back into the pin
8. Release inside the faint dashed ring: cancels cleanly
9. Start a gesture near any screen edge: it nudges inward so every direction is reachable
10. Your next click right after release goes to the app underneath (the overlay never eats clicks)
11. Hold still: a slow, calm breathing (not jitter); whip the cursor: it trails, sloshes, then catches up
12. Try each preset and a few themes; "Surprise me" gives a new palette each time
13. Haptics on a trackpad; "Soft Sounds" (menu bar) adds a very quiet tick and plip
14. Reduce Motion: no springs or wobble, same angles and dead zone

## If anything feels wrong

Escape, wait 12 s, **⌃⌥⌘P**, or `pkill -x Pluck`. Then look at `gesture.log`.
