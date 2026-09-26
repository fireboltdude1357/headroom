#!/bin/bash
# Builds a universal Headroom.app and Headroom.dmg into dist/. Run on a Mac with Xcode.
#
# Without SIGN_IDENTITY the app is ad-hoc signed, and Gatekeeper blocks it on other Macs until
# the user clicks Open Anyway in System Settings > Privacy & Security. To ship a build that
# opens normally, set:
#   SIGN_IDENTITY   a "Developer ID Application: Name (TEAMID)" identity in the keychain
#   NOTARY_PROFILE  a notarytool keychain profile, made once with `xcrun notarytool store-credentials`
# The script then signs with the hardened runtime, notarizes the DMG and staples the ticket.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${VERSION:-1.0.0}"
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
    codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$APP"
else
    codesign --force --sign - --timestamp=none "$APP"
fi

mkdir -p dist/dmg
cp -R "$APP" dist/dmg/
ln -s /Applications dist/dmg/Applications
hdiutil create -quiet -volname Headroom -srcfolder dist/dmg -format UDZO dist/Headroom.dmg
rm -rf dist/dmg

if [ -n "${SIGN_IDENTITY:-}" ]; then
    codesign --force --timestamp --sign "$SIGN_IDENTITY" dist/Headroom.dmg
    if [ -n "${NOTARY_PROFILE:-}" ]; then
        xcrun notarytool submit dist/Headroom.dmg --keychain-profile "$NOTARY_PROFILE" --wait
        xcrun stapler staple dist/Headroom.dmg
        spctl --assess --type open --context context:primary-signature --verbose dist/Headroom.dmg
    fi
fi
du -sh "$APP" dist/Headroom.dmg
