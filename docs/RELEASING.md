# Releasing

1. Update `CHANGELOG.md` and put the new number in `VERSION` (for example `0.2.0`).
2. Run `swift test` and `./scripts/build.sh`, then try the app by hand: trigger, cancel with `Esc`, the panic quit, and a couple of styles.
3. Commit, then tag and push: `git tag v0.2.0 && git push origin v0.2.0`. The **Release** workflow tests, packages and attaches `Twang-<version>.zip` (plus its SHA-256) to a GitHub release.

## Signing and notarizing

Without credentials `scripts/package.sh` produces an ad-hoc signed build. People can still run it (right-click, Open), but macOS will warn and Accessibility permission resets on each update. For a proper release you need an Apple Developer account:

```bash
SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
NOTARY_PROFILE=twang-notary \
./scripts/package.sh
```

Create the notary profile once with `xcrun notarytool store-credentials twang-notary`. To do this in CI, add the certificate and credentials as repository secrets and extend `release.yml`; none are configured today.

## Pack library

`./scripts/build-library.sh` zips the packs in `packs/examples` into `dist/packs/*.twangpack` and writes `library.json` with SHA-256 hashes. Set `PACK_BASE_URL` to where you will host the files, upload the folder, and give people the URL of `library.json`.
