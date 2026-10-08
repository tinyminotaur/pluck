# Shader preview (WebGL port)

Headless-Chromium render of the blob shader + radius profile, for checking the look on
machines without Metal (e.g. cloud sessions). It is a hand port of `ObsidianBlobMetal.swift`
and `BlobMass.swift` — keep it in sync when editing either.

    node scripts/preview/shot.js     # writes scripts/preview/out.png

Rows: facet 0 / 0.55 / 1.0. Columns: rest / medium stretch / long stretch with sag.
Needs Playwright with Chromium (`PLAYWRIGHT_BROWSERS_PATH`); adjust `require` / `executablePath` in `shot.js` if yours differ.

**Sync status:** the colour/ember/water/dome changes are ported, but the theme palette system (three-stop gradients,
fill, chrome), the action buds, and per-theme uniforms are **Metal-only**. Treat `ObsidianBlobMetal.swift` as the source
of truth and use `Pluck --render-themes` / `--render-compass` on a Mac for current looks.
