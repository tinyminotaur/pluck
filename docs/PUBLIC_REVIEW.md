# Pre-public review

Review of the repository for public release (Apache-2.0). The repo was already public when this was written.
Items are marked **Fixed**, **Open** (needs a decision or credentials) or **Note**.

## Licence
- **OK** `LICENSE` is the full Apache License 2.0 text.
- **Fixed** Added `NOTICE` (Apache asks that it be preserved by redistributors) and set the copyright line in `Info.plist` and README to "Tiny Minotaur and contributors". **Open:** confirm the legal entity name you want there.
- **Note** No third-party code or assets are bundled (no dependencies in `Package.swift`; sounds and art are generated in code). If that changes, list each in `NOTICE`.
- **Optional** `scripts/add-spdx.sh` adds `SPDX-License-Identifier: Apache-2.0` headers to every Swift file. Not run, because it touches every file.

## Secrets and history
- **OK** No keys, tokens or credentials in the tree or in git history (pattern scan of all revisions). `signing/` was never tracked and is gitignored.
- **OK** Commit authors are the maintainer and an AI co-author trailer; no personal addresses beyond the intended public one.
- **Note** `docs/research/notes/` holds raw, partly unverified research notes (some written during tool sessions, with sandbox paths). Consider deleting them and keeping only `docs/research/reports/`, which label sourced versus opinion claims.

## Security findings
1. **Fixed (was exploitable with real actions on):** `ActionRunner.revealInfo` put a file path inside AppleScript source unescaped, so a file named `x" & (do shell script "...") & "` could run shell commands when you used Get Info on it. Now goes through `AppleScriptEscape.quoted` (core, unit-tested).
2. **Fixed:** pack import extracted the archive *before* rejecting symlinks, so a zip with a symlink followed by a file written "through" it could escape the install folder, and the size limit was checked only after extraction (zip bomb). Now links are refused and the uncompressed size is checked up front, both from the archive listing.
3. **Fixed (trust claim vs code):** the README, Info.plist, setup screen, Settings and SECURITY.md say Pluck "never sends keystrokes", but the optional paste action posted a synthetic ⌘V. Paste now puts the clip on the pasteboard and you press ⌘V yourself, so the claim is true. (Revert is one function if you prefer auto-paste: then soften the claim instead.)
4. **Open (low):** the pack library's SHA-256 comes from the same index you fetched, so it protects against corrupted or swapped downloads but not a compromised library host. Say so in `docs/PACKS.md`, or sign the index.
5. **Open (low):** library index is fully downloaded before the 2 MB size check; use a streaming byte cap.
6. **Open (low):** GitHub Actions are pinned by tag (`actions/checkout@v4`), not commit SHA. Fine for now; pin before shipping signed releases. `ci.yml` uses `pull_request` (no secrets for forks) and `release.yml` runs only on tags: good.
7. **Note:** private APIs (`MultitouchSupport`, a CoreGraphics cursor call, `_AXUIElementGetWindow`) are loaded dynamically and fail safe. Documented in SECURITY.md. They make a Mac App Store release unlikely; direct download with notarization is the plan.

## Product and naming
- **Open** Bundle ID is the generic `com.pluck.app`. Use a domain you own, e.g. `co.tinyminotaur.<name>`, and change it *before* the first notarized release: changing it later resets users' Accessibility grants.
- **Open** The name "Pluck" collides with another macOS utility (`advegaf/pluck` on GitHub) and with trademark filings by Pluck, Inc. See `docs/NAMING.md`. `scripts/rename-project.sh` performs the rename mechanically.
- **Open** Signing and notarization need an Apple Developer account (see `docs/RELEASING.md`).
- **Open** Turn on GitHub private vulnerability reporting (Settings > Code security) since SECURITY.md points to it.
- **Open** Replace `example.com` in the sample pack library with the real host before advertising the library.
- **Note** `scripts/preview` (WebGL port) only covers the original liquid look; use `Pluck --render-styles` for the rest.
