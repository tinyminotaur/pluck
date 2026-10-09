#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

BUNDLE_ID="co.tinyminotaur.twang"
CERT_NAME="Twang Dev"

# Stable identity so Accessibility / Input Monitoring survive rebuilds.
"$ROOT/scripts/ensure-signing-identity.sh"

swift build -c release
BIN="$(swift build -c release --show-bin-path)/Twang"
APP="$ROOT/build/Twang.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Twang"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
echo -n 'APPL????' > "$APP/Contents/PkgInfo"
chmod +x "$APP/Contents/MacOS/Twang"

ENTITLEMENTS="$ROOT/Resources/Twang.entitlements"

# Prefer stable "Twang Dev"; fall back to any Apple Development identity if present.
SIGN_ID="$CERT_NAME"
if ! security find-identity -v -p codesigning 2>/dev/null | grep -F "\"$CERT_NAME\"" >/dev/null; then
  SIGN_ID=$(security find-identity -v -p codesigning 2>/dev/null | grep -E 'Apple Development|Developer ID Application' | head -1 | sed -E 's/.*"(.+)".*/\1/' || true)
fi

if [[ -z "${SIGN_ID}" ]]; then
  echo "ERROR: No stable signing identity. Refusing ad-hoc sign (it resets Accessibility every rebuild)."
  exit 1
fi

echo "Signing with: $SIGN_ID"

# Do NOT use --options runtime (hardened runtime) for local builds:
# it silently blocks TCC prompts (Input Monitoring never appears in Settings).
codesign --force --sign "$SIGN_ID" \
  --identifier "$BUNDLE_ID" \
  --entitlements "$ENTITLEMENTS" \
  "$APP/Contents/MacOS/Twang"

codesign --force --sign "$SIGN_ID" \
  --identifier "$BUNDLE_ID" \
  --entitlements "$ENTITLEMENTS" \
  "$APP"

# Verify not ad-hoc
if codesign -dv "$APP" 2>&1 | grep -q 'Signature=adhoc'; then
  echo "ERROR: App is still ad-hoc signed. Accessibility will keep resetting."
  codesign -dv --verbose=2 "$APP" 2>&1 | grep -E 'Identifier=|Authority=|Signature=' || true
  exit 1
fi

LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
if [[ -x "$LSREGISTER" ]]; then
  "$LSREGISTER" -f "$APP" >/dev/null 2>&1 || true
fi

echo "Built $APP"
codesign -dv --verbose=2 "$APP" 2>&1 | grep -E 'Identifier=|Authority=|Signature=|TeamIdentifier=' || true
echo ""
echo "Open with: open '$APP'"
echo "First launch after switching to stable signing: grant Accessibility ONCE."
echo "Later rebuilds should keep that grant."
