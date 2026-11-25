#!/bin/bash
# Signs the release .zip for Sparkle and writes dist/appcast.xml describing it.
# Run after scripts/package.sh. The appcast is published with the release, and
# apps read it from .../releases/latest/download/appcast.xml.
#
#   SPARKLE_PRIVATE_KEY=... scripts/make-appcast.sh    # key as exported by generate_keys -x
#   scripts/make-appcast.sh                           # key from your login keychain
set -euo pipefail
cd "$(dirname "$0")/.."

APP="build/BarManager.app"
VERSION="$(tr -d '[:space:]' < VERSION)"
ZIP="dist/BarManager-$VERSION.zip"
OUT="dist/appcast.xml"
REPO_URL="https://github.com/valyus/barmanager"
[ -f "$ZIP" ] || { echo "Run scripts/package.sh first" >&2; exit 1; }

swift package resolve >/dev/null
SIGN_UPDATE="$(find .build/artifacts -path '*/Sparkle/bin/sign_update' -type f | head -1)"
[ -x "$SIGN_UPDATE" ] || { echo "Can't find Sparkle's sign_update" >&2; exit 1; }

if [ -n "${SPARKLE_PRIVATE_KEY:-}" ]; then
    SIGNATURE="$(printf '%s' "$SPARKLE_PRIVATE_KEY" | "$SIGN_UPDATE" --ed-key-file - -p "$ZIP")"
else
    SIGNATURE="$("$SIGN_UPDATE" -p "$ZIP")"
fi
# Make sure the app that will download this trusts the key it was signed with.
swift scripts/verify-update-signature.swift "$APP" "$ZIP" "$SIGNATURE"

BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP/Contents/Info.plist")"
MIN_OS="$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$APP/Contents/Info.plist")"
LENGTH="$(stat -f %z "$ZIP")"

python3 - "$VERSION" "$BUILD" "$MIN_OS" "$LENGTH" "$SIGNATURE" "$REPO_URL" "$OUT" <<'PY'
import html, re, sys
from email.utils import formatdate

version, build, min_os, length, signature, repo, out = sys.argv[1:]

# This version's changelog entry, as simple HTML for Sparkle's update window.
notes, on = [], False
for line in open("CHANGELOG.md", encoding="utf-8"):
    if re.match(r"^## \[", line):
        on = line.startswith(f"## [{version}]")
        continue
    if on:
        notes.append(line.rstrip("\n"))

def inline(text):
    text = html.escape(text, quote=False)
    text = re.sub(r"\*\*(.+?)\*\*", r"<b>\1</b>", text)
    text = re.sub(r"`(.+?)`", r"<code>\1</code>", text)
    def link(m):
        target = m.group(2)
        if not re.match(r"^[a-z]+:", target):  # relative to the repository
            target = f"{repo}/blob/main/{target}"
        return f'<a href="{target}">{m.group(1)}</a>'
    return re.sub(r"\[(.+?)\]\((.+?)\)", link, text)

parts, in_list = [], False
for line in notes:
    if line.startswith("- "):
        if not in_list:
            parts.append("<ul>")
            in_list = True
        parts.append(f"<li>{inline(line[2:])}</li>")
        continue
    if in_list:
        parts.append("</ul>")
        in_list = False
    if line.startswith("### "):
        parts.append(f"<h3>{inline(line[4:])}</h3>")
    elif line.strip():
        parts.append(f"<p>{inline(line)}</p>")
if in_list:
    parts.append("</ul>")
description = "\n".join(parts) or f"<p>BarManager {html.escape(version)}</p>"

url = f"{repo}/releases/download/v{version}/BarManager-{version}.zip"
xml = f"""<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>BarManager</title>
    <link>{repo}</link>
    <item>
      <title>BarManager {html.escape(version)}</title>
      <pubDate>{formatdate(usegmt=True)}</pubDate>
      <sparkle:version>{html.escape(build)}</sparkle:version>
      <sparkle:shortVersionString>{html.escape(version)}</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>{html.escape(min_os)}</sparkle:minimumSystemVersion>
      <sparkle:fullReleaseNotesLink>{repo}/releases/tag/v{html.escape(version)}</sparkle:fullReleaseNotesLink>
      <description><![CDATA[{description}]]></description>
      <enclosure url="{html.escape(url)}" length="{length}" type="application/octet-stream" sparkle:edSignature="{html.escape(signature)}"/>
    </item>
  </channel>
</rss>
"""
open(out, "w", encoding="utf-8").write(xml)
PY
xmllint --noout "$OUT"
echo "Wrote $OUT for $VERSION (build $BUILD)"
