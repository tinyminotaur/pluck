#!/bin/bash
# Build a distributable Pluck.app and zip it.
#   SIGN_IDENTITY="Developer ID Application: Name (TEAMID)"  sign with hardened runtime (otherwise ad-hoc, local testing only)
#   NOTARY_PROFILE=name   after signing, notarize with `xcrun notarytool` (a keychain profile) and staple
# Output: dist/Pluck-<version>.zip
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"; cd "$ROOT"
VERSION="$(tr -d '[:space:]' < VERSION)"
BUILD="${BUILD_NUMBER:-$(git rev-list --count HEAD 2>/dev/null || echo 1)}"
APP="$ROOT/dist/Pluck.app"
rm -rf "$ROOT/dist/Pluck.app"; mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

swift build -c release --arch arm64 --arch x86_64
BIN="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)/Pluck"
cp "$BIN" "$APP/Contents/MacOS/Pluck"
cp Resources/Info.plist "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" -c "Set :CFBundleVersion $BUILD" "$APP/Contents/Info.plist"
echo -n 'APPL????' > "$APP/Contents/PkgInfo"

if [[ -n "${SIGN_IDENTITY:-}" ]]; then
  codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" --entitlements Resources/Pluck.entitlements "$APP"
else
  echo "SIGN_IDENTITY not set: ad-hoc signing (fine for testing; Gatekeeper will warn and Accessibility resets on every build)."
  codesign --force --sign - --entitlements Resources/Pluck.entitlements "$APP"
fi
codesign --verify --strict "$APP"

ZIP="$ROOT/dist/Pluck-$VERSION.zip"
rm -f "$ZIP"; ditto -c -k --keepParent "$APP" "$ZIP"
if [[ -n "${SIGN_IDENTITY:-}" && -n "${NOTARY_PROFILE:-}" ]]; then
  xcrun notarytool submit "$ZIP" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$APP"
  rm -f "$ZIP"; ditto -c -k --keepParent "$APP" "$ZIP"
fi
shasum -a 256 "$ZIP" | tee "$ZIP.sha256"
echo "Packaged $ZIP"
