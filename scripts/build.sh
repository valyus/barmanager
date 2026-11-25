#!/bin/bash
# Builds BarManager.app (release) into ./build and signs it.
#
#   scripts/build.sh                     # sign with Developer ID / Apple Development if present, else ad hoc
#   BARMANAGER_SIGN_ID=- scripts/build.sh  # force ad-hoc signing (CI)
#
# In-app updates turn on when sparkle-public-key.txt exists (or SPARKLE_PUBLIC_KEY
# is set): its key goes into Info.plist so the app only installs updates signed
# with the matching private key. scripts/set-sparkle-key.sh creates it.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="$(tr -d '[:space:]' < VERSION)"
# Build number: commit count, so every published build is higher than the last.
BUILD="$(git rev-list --count HEAD 2>/dev/null || echo 1)"

# SPARKLE_FEED_URL points a test build at another appcast.
FEED_URL="${SPARKLE_FEED_URL:-https://github.com/valyus/barmanager/releases/latest/download/appcast.xml}"
PUBLIC_KEY="${SPARKLE_PUBLIC_KEY:-}"
[ -z "$PUBLIC_KEY" ] && [ -f sparkle-public-key.txt ] && PUBLIC_KEY="$(tr -d '[:space:]' < sparkle-public-key.txt)"

swift build -c release
BIN_DIR="$(swift build -c release --show-bin-path)"

APP="build/BarManager.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/BarManager" "$APP/Contents/MacOS/BarManager"
# Sparkle ships as a framework; keep its symlinks intact. (Versions before
# 1.2.0 have no Sparkle, and the Release workflow can rebuild old tags.)
HAS_SPARKLE=false
if [ -d "$BIN_DIR/Sparkle.framework" ]; then
    HAS_SPARKLE=true
    mkdir -p "$APP/Contents/Frameworks"
    ditto "$BIN_DIR/Sparkle.framework" "$APP/Contents/Frameworks/Sparkle.framework"
    install_name_tool -add_rpath "@executable_path/../Frameworks" "$APP/Contents/MacOS/BarManager"
fi
$HAS_SPARKLE || PUBLIC_KEY=""

UPDATE_KEYS=""
if [ -n "$PUBLIC_KEY" ]; then
    UPDATE_KEYS="<key>SUFeedURL</key><string>${FEED_URL}</string>
    <key>SUPublicEDKey</key><string>${PUBLIC_KEY}</string>
    <key>SUEnableAutomaticChecks</key><true/>"
fi

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
    ${UPDATE_KEYS}
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
    sign() { codesign --force --sign - "$@"; }
else
    # Hardened runtime + secure timestamp are required for notarization.
    sign() { codesign --force --options runtime --timestamp --sign "$SIGN_ID" "$@"; }
fi
# Inside out, as Sparkle's docs describe: its helpers, then the framework, then the app.
if $HAS_SPARKLE; then
    SPARKLE="$APP/Contents/Frameworks/Sparkle.framework/Versions/B"
    sign "$SPARKLE/XPCServices/Installer.xpc"
    sign --preserve-metadata=entitlements "$SPARKLE/XPCServices/Downloader.xpc"
    sign "$SPARKLE/Autoupdate"
    sign "$SPARKLE/Updater.app"
    sign "$APP/Contents/Frameworks/Sparkle.framework"
fi
sign "$APP"
codesign --verify --strict --deep "$APP"
if [ -n "$PUBLIC_KEY" ]; then updates="updates on"; else updates="updates off: no sparkle-public-key.txt"; fi
echo "Built $APP ($VERSION, build $BUILD, $updates)"
