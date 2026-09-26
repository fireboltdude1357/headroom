#!/bin/bash
# One-time setup so scripts/bundle.sh can sign and notarize over SSH, where the login keychain
# stays locked. Run it in Terminal (not over SSH) on the Mac that holds the Developer ID certificate:
#
#   APPLE_ID=you@example.com scripts/setup-signing.sh
#
# It creates a separate keychain whose password is kept in ~/.config/headroom, copies your signing
# identities into it, and stores notarytool credentials there. macOS asks you to allow the export,
# and notarytool asks for an app-specific password (make one at account.apple.com).
set -euo pipefail
: "${APPLE_ID:?Set APPLE_ID to the Apple ID that belongs to the developer team}"
case "$APPLE_ID" in *@example.com) echo "APPLE_ID is still the example address." >&2; exit 1 ;; esac
TEAM_ID="${TEAM_ID:-N6GFPFX8A2}"
KEYCHAIN="$HOME/Library/Keychains/headroom-signing.keychain-db"
PASSFILE="$HOME/.config/headroom/signing-keychain-password"

umask 077
mkdir -p "$(dirname "$PASSFILE")"
[ -f "$PASSFILE" ] || openssl rand -base64 24 > "$PASSFILE"
PASS="$(cat "$PASSFILE")"

[ -f "$KEYCHAIN" ] || security create-keychain -p "$PASS" "$KEYCHAIN"
security set-keychain-settings "$KEYCHAIN"   # never auto-lock
security unlock-keychain -p "$PASS" "$KEYCHAIN"

# Safe to re-run: the identities are only copied the first time.
if ! security find-identity -v -p codesigning "$KEYCHAIN" | grep -q "Developer ID Application"; then
    TMP="$(mktemp -d)"
    trap 'rm -rf "$TMP"' EXIT
    security export -k login.keychain-db -t identities -f pkcs12 -P "$PASS" -o "$TMP/identities.p12"
    security import "$TMP/identities.p12" -k "$KEYCHAIN" -P "$PASS" -T /usr/bin/codesign
    security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$PASS" "$KEYCHAIN" >/dev/null
fi

security find-identity -v -p codesigning "$KEYCHAIN" | grep "Developer ID Application" \
    || { echo "No Developer ID Application identity was copied." >&2; exit 1; }

xcrun notarytool store-credentials headroom-notary --apple-id "$APPLE_ID" --team-id "$TEAM_ID" --keychain "$KEYCHAIN"
echo "Done. scripts/bundle.sh will now sign and notarize automatically."
