#!/bin/bash
# Packages build/BarManager.app into dist/ as a .zip and a .dmg, and notarizes
# them when credentials are set. Run scripts/build.sh first.
#
# Notarization (optional) uses an App Store Connect API key:
#   NOTARY_KEY_PATH  path to the AuthKey_XXXX.p8 file
#   NOTARY_KEY_ID    the key ID
#   NOTARY_ISSUER    the issuer ID
# Set REQUIRE_NOTARIZATION=1 to fail instead of packaging an unnotarized build.
#
# The .dmg is signed with the same Developer ID as the app (BARMANAGER_SIGN_ID,
# else the first Developer ID Application identity), when there is one.
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
elif [ "${REQUIRE_NOTARIZATION:-}" = "1" ]; then
    echo "REQUIRE_NOTARIZATION is set but NOTARY_KEY_PATH, NOTARY_KEY_ID or NOTARY_ISSUER isn't" >&2
    exit 1
fi

# Notarization needs a Developer ID signature; catch an ad-hoc or Apple
# Development build here rather than after a long wait for Apple.
signature="$(codesign -dv --verbose=2 "$APP" 2>&1 || true)"
authority="$(awk -F= '/^Authority=/ {print $2; exit}' <<<"$signature")"
if $can_notarize && [[ "$authority" != "Developer ID Application:"* ]]; then
    echo "Can't notarize: $APP is signed by \"${authority:-ad hoc}\", not a Developer ID Application certificate" >&2
    exit 1
fi
dmg_id="${BARMANAGER_SIGN_ID:-}"
[ "$dmg_id" = "-" ] && dmg_id=""
if [ -z "$dmg_id" ] && [[ "$authority" == "Developer ID Application:"* ]]; then
    identities="$(security find-identity -v -p codesigning)"
    dmg_id="$(awk '/Developer ID Application/ {print $2; exit}' <<<"$identities")"
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
if [ -n "$dmg_id" ]; then
    codesign --force --timestamp --sign "$dmg_id" "$DMG"
fi

if $can_notarize; then
    notarize "$DMG"
    xcrun stapler staple "$DMG"
else
    echo "Note: not notarized (NOTARY_* not set). Gatekeeper will warn people who download it."
fi

(cd dist && shasum -a 256 "$(basename "$ZIP")" "$(basename "$DMG")" > "SHA256SUMS-$VERSION.txt")
echo "Packaged $ZIP and $DMG"
