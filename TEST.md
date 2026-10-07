# Pluck Feel Lab — safe testing

This build **cannot lock your keyboard or mouse**.

## Guarantees

- Listen-only (`NSEvent` monitors) — events always pass through to the system
- **No** `CGEventTap` (the thing that can swallow input)
- **No** synthesizing clicks/keys
- **No** System Settings UI automation / injected keystrokes
- Gesture auto-cancels after **20 seconds**
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

## If anything feels wrong

- Escape, or wait 20s
- Menu bar drop → **Reset Pointer / Gesture** or **Quit Pluck**
- Panic: **⌃⌥⌘P**
