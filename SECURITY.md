# Security

## Reporting a vulnerability

Please **do not open a public issue** for a security problem. Use GitHub's private reporting:
*Security > Report a vulnerability* on this repository. Include steps to reproduce and the macOS version. You will get a
reply within a few days.

## What Twang can and cannot do

- **Input:** Twang only *listens* to mouse, keyboard and trackpad events (it needs the Accessibility permission for that).
  It never installs an event tap and never synthesizes input, so it cannot block or inject keystrokes or clicks.
- **Packs:** community animation packs are JSON data with a small formula language. They cannot run code, read files
  outside the pack, or use the network. Pack archives are validated before install: no path escapes, no links, only
  JSON/PNG/JPEG, size and count limits (`Sources/Twang/Packs/PackLibrary.swift`).
- **Network:** only when you press a button (refresh the online library, install a pack). HTTPS only, and every download is
  checked against a published SHA-256. No telemetry, no analytics.
- **Audio:** the optional Equalizer-follows-music setting captures *system audio* via ScreenCaptureKit (macOS asks for
  Screen Recording permission). Only 24 level numbers are used; nothing is recorded or stored. Off by default.
- **Clipboard / actions:** the optional "real actions" beta (off by default) can read the clipboard and run actions such as
  copy, share and window tiling. Clipboard history is kept in memory only.
- **Private APIs:** the optional three-finger trigger uses the private `MultitouchSupport` framework (off by default) and
  the cursor-hiding fix uses a private CoreGraphics call; both are loaded dynamically and fail safe.

## Supported versions

The latest release. This is a young project; fixes land on `main`.
