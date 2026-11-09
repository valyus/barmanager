#!/bin/bash
# Builds BarManager.app (release) into ./build and signs it.
#
#   scripts/build.sh                     # sign with Developer ID / Apple Development if present, else ad hoc
#   BARMANAGER_SIGN_ID=- scripts/build.sh  # force ad-hoc signing (CI)
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="$(tr -d '[:space:]' < VERSION)"
# Build number: commit count, so every published build is higher than the last.
BUILD="$(git rev-list --count HEAD 2>/dev/null || echo 1)"

swift build -c release
BIN="$(swift build -c release --show-bin-path)/BarManager"

APP="build/BarManager.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/BarManager"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>BarManager</string>
    <key>CFBundleDisplayName</key><string>BarManager</string>
    <key>CFBundleIdentifier</key><string>com.ovalius.barmanager</string>
    <key>CFBundleExecutable</key><string>BarManager</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>${VERSION}</string>
    <key>CFBundleVersion</key><string>${BUILD}</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSHumanReadableCopyright</key><string>© $(date +%Y) Alex Valius</string>
</dict>
</plist>
PLIST
plutil -lint "$APP/Contents/Info.plist" >/dev/null

# Sign with a stable identity when one exists so macOS keeps permissions across
# rebuilds. Developer ID (needed for notarized releases) wins over Apple Development.
identities="$(security find-identity -v -p codesigning 2>/dev/null || true)"
default_id="$(awk '/Developer ID Application/ {print $2; exit}' <<<"$identities")"
[ -z "$default_id" ] && default_id="$(awk '/Apple Development/ {print $2; exit}' <<<"$identities")"
SIGN_ID="${BARMANAGER_SIGN_ID:-${default_id:--}}"

if [ "$SIGN_ID" = "-" ]; then
    codesign --force --sign - "$APP"
else
    # Hardened runtime + secure timestamp are required for notarization.
    codesign --force --options runtime --timestamp --sign "$SIGN_ID" "$APP"
fi
codesign --verify --strict "$APP"
echo "Built $APP ($VERSION, build $BUILD)"
