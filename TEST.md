# Pluck Feel Lab — safe testing

This build **cannot lock your keyboard or mouse**.

## Guarantees

- Listen-only (`NSEvent` monitors) — events always pass through to the system
- **No** `CGEventTap` (the thing that can swallow input)
- **No** synthesizing clicks/keys
- **No** System Settings UI automation / injected keystrokes
- Gesture auto-cancels after **12 seconds without movement** (30 min hard cap)
- **Escape** cancels
- Panic quit: **Control + Option + Command + P**
- Menu bar → **Quit Pluck** always works (events aren’t swallowed)

## Setup (once)

1. Open `build/Pluck.app`
2. Enable **Accessibility** for Pluck if asked (should stick with **Pluck Dev** signing)
3. Use the Feel Lab guide window

Input Monitoring is **not required** and is **not automated**.

## What to test

1. Hold left → press right (or reverse)
2. Blob should rise and cover the cursor
3. Move — one connected stretch; lobes highlight by direction
4. Release — guide shows North/East/South/West or Canceled

## Fidget feel (check these too)

5. Release a long pull — the blob should snap back to the pin with an overshoot wobble, then melt
6. Hold still — the blob should gently breathe
7. Stretch far — facets should sharpen; move the mouse — glints should sweep across the planes
8. Re-grab immediately after a release — no cooldown, the old recoil is cut
9. On a trackpad: haptic tick when a direction latches and a ratchet click every ~56 pt of stretch
10. Your next click right after release must go to the app underneath (the overlay must not eat it)

## If anything feels wrong

- Escape, or stop moving for 12s
- Menu bar drop → **Reset Pointer / Gesture** or **Quit Pluck**
- Panic: **⌃⌥⌘P**
