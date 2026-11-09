#!/bin/bash
# Packages build/BarManager.app into dist/ as a .zip and a .dmg, and notarizes
# them when credentials are set. Run scripts/build.sh first.
#
# Notarization (optional) uses an App Store Connect API key:
#   NOTARY_KEY_PATH  path to the AuthKey_XXXX.p8 file
#   NOTARY_KEY_ID    the key ID
#   NOTARY_ISSUER    the issuer ID
set -euo pipefail
cd "$(dirname "$0")/.."

APP="build/BarManager.app"
VERSION="$(tr -d '[:space:]' < VERSION)"
[ -d "$APP" ] || { echo "Run scripts/build.sh first" >&2; exit 1; }

mkdir -p dist
ZIP="dist/BarManager-$VERSION.zip"
DMG="dist/BarManager-$VERSION.dmg"
rm -f "$ZIP" "$DMG"

notarize() {
    xcrun notarytool submit "$1" --wait \
        --key "$NOTARY_KEY_PATH" --key-id "$NOTARY_KEY_ID" --issuer "$NOTARY_ISSUER"
}

can_notarize=false
if [ -n "${NOTARY_KEY_PATH:-}" ] && [ -n "${NOTARY_KEY_ID:-}" ] && [ -n "${NOTARY_ISSUER:-}" ]; then
    can_notarize=true
fi

if $can_notarize; then
    # Notarize the app itself, then staple the ticket so it opens offline.
    ditto -c -k --keepParent "$APP" "dist/notarize.zip"
    notarize "dist/notarize.zip"
    rm "dist/notarize.zip"
    xcrun stapler staple "$APP"
fi

ditto -c -k --keepParent "$APP" "$ZIP"

STAGE="$(mktemp -d)"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -quiet -volname "BarManager" -srcfolder "$STAGE" -ov -format UDZO "$DMG"
rm -rf "$STAGE"

if $can_notarize; then
    notarize "$DMG"
    xcrun stapler staple "$DMG"
else
    echo "Note: not notarized (NOTARY_* not set). Gatekeeper will warn people who download it."
fi

(cd dist && shasum -a 256 "$(basename "$ZIP")" "$(basename "$DMG")" > "SHA256SUMS-$VERSION.txt")
echo "Packaged $ZIP and $DMG"
