#!/bin/bash
# Sets up the key that signs in-app updates. Run once.
#
#   scripts/set-sparkle-key.sh
#
# 1. Creates an update signing key in your login keychain with Sparkle's
#    generate_keys, or reuses the one already there (macOS may ask to allow
#    keychain access).
# 2. Writes its public half to sparkle-public-key.txt. Commit that file: builds
#    put it in the app, which then installs only updates signed with your key.
# 3. Uploads the private half as the SPARKLE_PRIVATE_KEY repository secret, so
#    the Release workflow can sign updates. Needs `gh` signed in.
#
# Back up the private key (generate_keys -x <file>, then into a password
# manager). If it's lost, installed copies can't be updated any more.
set -euo pipefail
cd "$(dirname "$0")/.."

swift package resolve >/dev/null
GENERATE_KEYS="$(find .build/artifacts -path '*/Sparkle/bin/generate_keys' -type f | head -1)"
[ -x "$GENERATE_KEYS" ] || { echo "Can't find Sparkle's generate_keys" >&2; exit 1; }
command -v gh >/dev/null || { echo "Install the GitHub CLI (gh) first" >&2; exit 1; }
REPO="$(gh repo view --json nameWithOwner -q .nameWithOwner)"

if [ -f sparkle-public-key.txt ] && ! "$GENERATE_KEYS" -p >/dev/null 2>&1; then
    echo "sparkle-public-key.txt exists but there's no key in your keychain." >&2
    echo "Import the matching private key first: $GENERATE_KEYS -f <file>" >&2
    exit 1
fi

"$GENERATE_KEYS" >/dev/null            # creates the key only if there isn't one
PUBLIC_KEY="$("$GENERATE_KEYS" -p)"
if [ -f sparkle-public-key.txt ] && [ "$(tr -d '[:space:]' < sparkle-public-key.txt)" != "$PUBLIC_KEY" ]; then
    echo "The key in your keychain doesn't match sparkle-public-key.txt. Installed copies trust the file's key;" >&2
    echo "import that private key instead of replacing the file." >&2
    exit 1
fi
echo "$PUBLIC_KEY" > sparkle-public-key.txt
echo "✓ Public key in sparkle-public-key.txt: $PUBLIC_KEY"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
"$GENERATE_KEYS" -x "$TMP/key" >/dev/null
gh secret set SPARKLE_PRIVATE_KEY --repo "$REPO" < "$TMP/key"
echo "✓ SPARKLE_PRIVATE_KEY set on $REPO"
echo
echo "Next: commit sparkle-public-key.txt, and back up the private key in a password manager:"
echo "  $GENERATE_KEYS -x ~/Desktop/barmanager-sparkle-key.txt"
