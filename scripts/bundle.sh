#!/bin/bash
# Builds a universal Headroom.app and Headroom.dmg into dist/. Run on a Mac with Xcode.
#
# If scripts/setup-signing.sh has been run on this Mac, the build is signed with its Developer ID,
# notarized and stapled, which also works over SSH. Otherwise the app is ad-hoc signed, and
# Gatekeeper blocks it on other Macs until the user clicks Open Anyway in System Settings >
# Privacy & Security. SIGN_IDENTITY and NOTARY_PROFILE override what the setup found.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${VERSION:-1.0.0}"

SIGNING_KEYCHAIN="$HOME/Library/Keychains/headroom-signing.keychain-db"
KEYCHAIN_ARGS=()
if [ -f "$SIGNING_KEYCHAIN" ]; then
    security unlock-keychain -p "$(cat "$HOME/.config/headroom/signing-keychain-password")" "$SIGNING_KEYCHAIN"
    KEYCHAIN_ARGS=(--keychain "$SIGNING_KEYCHAIN")
    # The SHA-1 hash, not the name, so a renewed certificate with the same name isn't ambiguous.
    SIGN_IDENTITY="${SIGN_IDENTITY:-$(security find-identity -v -p codesigning "$SIGNING_KEYCHAIN" \
        | awk '/Developer ID Application/ { print $2; exit }')}"
    # A release keychain without a valid identity (say, an expired certificate) must not quietly
    # produce an unsigned build that the site then serves as notarized.
    [ -n "$SIGN_IDENTITY" ] || { echo "No valid Developer ID identity in $SIGNING_KEYCHAIN" >&2; exit 1; }
    NOTARY_PROFILE="${NOTARY_PROFILE:-headroom-notary}"
fi

# Submits a file to Apple, waits, and fails unless Apple accepts it.
notarize() {
    local out
    out="$(xcrun notarytool submit "$1" --keychain-profile "$NOTARY_PROFILE" ${KEYCHAIN_ARGS[@]+"${KEYCHAIN_ARGS[@]}"} --wait)"
    echo "$out"
    echo "$out" | grep -q "status: Accepted" || { echo "Notarization of $1 was not accepted" >&2; exit 1; }
}
APP="dist/Headroom.app"

swift build -c release --arch arm64 --arch x86_64
BIN="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)/Headroom"

rm -rf dist/Headroom.app dist/Headroom.dmg dist/dmg
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Headroom"
[ -f Resources/AppIcon.icns ] && cp Resources/AppIcon.icns "$APP/Contents/Resources/"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>Headroom</string>
    <key>CFBundleDisplayName</key><string>Headroom</string>
    <key>CFBundleIdentifier</key><string>dev.headroom.Headroom</string>
    <key>CFBundleExecutable</key><string>Headroom</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>${VERSION}</string>
    <key>CFBundleVersion</key><string>${VERSION}</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSHumanReadableCopyright</key><string>Headroom measures files itself, so totals differ from Storage settings.</string>
</dict>
</plist>
PLIST

if [ -n "${SIGN_IDENTITY:-}" ]; then
    codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" ${KEYCHAIN_ARGS[@]+"${KEYCHAIN_ARGS[@]}"} "$APP"
    if [ -n "${NOTARY_PROFILE:-}" ]; then
        # Staple the app too, so a copy in Applications passes Gatekeeper even offline.
        ditto -c -k --keepParent "$APP" dist/Headroom-notarize.zip
        notarize dist/Headroom-notarize.zip
        rm dist/Headroom-notarize.zip
        xcrun stapler staple "$APP"
    fi
else
    codesign --force --sign - --timestamp=none "$APP"
fi

mkdir -p dist/dmg
cp -R "$APP" dist/dmg/
ln -s /Applications dist/dmg/Applications
hdiutil create -quiet -volname Headroom -srcfolder dist/dmg -format UDZO dist/Headroom.dmg
rm -rf dist/dmg

if [ -n "${SIGN_IDENTITY:-}" ]; then
    codesign --force --timestamp --sign "$SIGN_IDENTITY" ${KEYCHAIN_ARGS[@]+"${KEYCHAIN_ARGS[@]}"} dist/Headroom.dmg
    if [ -n "${NOTARY_PROFILE:-}" ]; then
        notarize dist/Headroom.dmg
        xcrun stapler staple dist/Headroom.dmg
        spctl --assess --type open --context context:primary-signature --verbose dist/Headroom.dmg
    fi
fi
du -sh "$APP" dist/Headroom.dmg
