#!/bin/zsh
# One-time: create a local code-signing identity ("fdev Local Signing") in your login keychain.
# With a stable identity, macOS keeps fdev's Accessibility permission across rebuilds
# (ad-hoc signatures change every build, so macOS treats each build as a new app).
# macOS will ask for your login password once, to trust the certificate for code signing.
set -euo pipefail

NAME="fdev Local Signing"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

if security find-identity -v -p codesigning | grep -q "$NAME"; then
  echo "✓ '$NAME' already exists — nothing to do."
  exit 0
fi

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
  -keyout "$TMP/key.pem" -out "$TMP/cert.pem" -subj "/CN=$NAME" \
  -addext "keyUsage=critical,digitalSignature" \
  -addext "extendedKeyUsage=critical,codeSigning" \
  -addext "basicConstraints=critical,CA:false" 2>/dev/null

openssl pkcs12 -export -inkey "$TMP/key.pem" -in "$TMP/cert.pem" \
  -out "$TMP/fdev.p12" -passout pass:fdev

security import "$TMP/fdev.p12" -k "$KEYCHAIN" -P fdev -T /usr/bin/codesign
security add-trusted-cert -r trustRoot -p codeSign -k "$KEYCHAIN" "$TMP/cert.pem"

echo "✓ Created '$NAME'. Now run ./build.sh — fdev will be signed with it."
echo "  Then grant Accessibility once more; it will stick from now on."
