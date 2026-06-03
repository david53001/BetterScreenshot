#!/bin/bash
# One-time, fully non-interactive setup of a STABLE self-signed code-signing
# identity for BetterScreenshot.
#
# Why: ad-hoc signed apps are identified by their code hash, which changes on
# every rebuild, so macOS resets Screen-Recording (TCC) permission each time.
# Signing with a stable certificate gives the app a constant "designated
# requirement", so you grant Screen Recording ONCE and it persists across every
# future rebuild.
#
# The identity lives in a dedicated keychain (not your login keychain) whose
# password is known to this script, which lets us pre-authorize `codesign` to
# use the key without any GUI prompt. The keychain holds nothing but this local,
# self-signed code-signing cert.
#
# Idempotent: safe to run repeatedly; it only creates the identity once (so the
# certificate — and therefore the granted permission — stays stable).
set -euo pipefail

IDENTITY="BetterScreenshot Code Signing"
KEYCHAIN="$HOME/Library/Keychains/betterscreenshot-signing.keychain-db"
KEYCHAIN_PW="betterscreenshot-local"

if security find-identity -p codesigning "$KEYCHAIN" 2>/dev/null | grep -q "$IDENTITY"; then
    echo "Signing identity '$IDENTITY' already exists — nothing to do."
    exit 0
fi

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

echo "Generating self-signed code-signing certificate…"
openssl req -x509 -newkey rsa:2048 -nodes \
    -keyout "$TMP/key.pem" -out "$TMP/cert.pem" -days 3650 \
    -subj "/CN=$IDENTITY" \
    -addext "keyUsage=critical,digitalSignature" \
    -addext "extendedKeyUsage=critical,codeSigning" \
    -addext "basicConstraints=critical,CA:false" 2>/dev/null
openssl pkcs12 -export -inkey "$TMP/key.pem" -in "$TMP/cert.pem" \
    -out "$TMP/cert.p12" -passout pass:"$KEYCHAIN_PW" -name "$IDENTITY" 2>/dev/null

if [ ! -f "$KEYCHAIN" ]; then
    security create-keychain -p "$KEYCHAIN_PW" "$KEYCHAIN"
fi
security set-keychain-settings "$KEYCHAIN"                 # no auto-lock timeout
security unlock-keychain -p "$KEYCHAIN_PW" "$KEYCHAIN"
security import "$TMP/cert.p12" -k "$KEYCHAIN" -P "$KEYCHAIN_PW" -T /usr/bin/codesign -A
# Pre-authorize codesign so signing never shows a keychain prompt.
security set-key-partition-list -S apple-tool:,apple:,codesign: \
    -s -k "$KEYCHAIN_PW" "$KEYCHAIN" >/dev/null

# Make sure the keychain is on the user search list (so codesign finds it),
# without dropping the existing ones.
if ! security list-keychains -d user | grep -q "$KEYCHAIN"; then
    EXISTING="$(security list-keychains -d user | sed -e 's/^[[:space:]]*//' -e 's/"//g')"
    # shellcheck disable=SC2086
    security list-keychains -d user -s "$KEYCHAIN" $EXISTING
fi

echo "Created stable signing identity '$IDENTITY'."
echo "Next: run scripts/build-app.sh, launch the app, and grant Screen Recording"
echo "once. It will then persist across all future rebuilds."
