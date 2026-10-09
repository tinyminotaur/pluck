#!/bin/bash
# Creates a stable local code-signing identity "Twang Dev" once.
# Ad-hoc signatures change every rebuild → macOS Accessibility resets every time.
# Signing with the same certificate keeps TCC grants across rebuilds.
set -euo pipefail

CERT_NAME="Twang Dev"
KEYCHAIN="${HOME}/Library/Keychains/login.keychain-db"
SIGNING_DIR="$(cd "$(dirname "$0")/.." && pwd)/signing"
P12_PASS='twang-local-dev'
mkdir -p "$SIGNING_DIR"

if security find-identity -v -p codesigning 2>/dev/null | grep -F "\"$CERT_NAME\"" >/dev/null; then
  echo "Using existing codesigning identity: $CERT_NAME"
  exit 0
fi

echo "Creating stable codesigning identity: $CERT_NAME"

CNF="$SIGNING_DIR/twang-dev.cnf"
KEY="$SIGNING_DIR/twang-dev.key"
CRT="$SIGNING_DIR/twang-dev.crt"
P12="$SIGNING_DIR/twang-dev.p12"

cat > "$CNF" <<'EOF'
[req]
distinguished_name = req_distinguished_name
x509_extensions = v3_req
prompt = no

[req_distinguished_name]
CN = Twang Dev
O = Twang Local Signing
C = US

[v3_req]
basicConstraints = critical,CA:FALSE
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
EOF

openssl req -x509 -newkey rsa:2048 -sha256 -days 3650 -nodes \
  -keyout "$KEY" -out "$CRT" -config "$CNF" -extensions v3_req >/dev/null 2>&1

# Modern OpenSSL PKCS12 needs -legacy for macOS Security.framework import.
if ! openssl pkcs12 -export -legacy -out "$P12" -inkey "$KEY" -in "$CRT" \
    -name "$CERT_NAME" -passout "pass:$P12_PASS" 2>/dev/null; then
  openssl pkcs12 -export -out "$P12" -inkey "$KEY" -in "$CRT" \
    -name "$CERT_NAME" -passout "pass:$P12_PASS" >/dev/null 2>&1
fi

security import "$P12" -k "$KEYCHAIN" -P "$P12_PASS" -A \
  -T /usr/bin/codesign -T /usr/bin/security

security add-trusted-cert -d -r trustRoot -k "$KEYCHAIN" "$CRT" 2>/dev/null || true
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "" "$KEYCHAIN" >/dev/null 2>&1 || true

chmod 600 "$KEY" "$P12" 2>/dev/null || true

if ! security find-identity -v -p codesigning 2>/dev/null | grep -F "\"$CERT_NAME\"" >/dev/null; then
  echo "ERROR: Failed to create '$CERT_NAME' identity."
  exit 1
fi

echo "Created codesigning identity: $CERT_NAME"
echo "Grant Accessibility ONCE after the next launch — it should stick across rebuilds."
