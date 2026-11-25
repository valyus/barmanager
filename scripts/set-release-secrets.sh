#!/bin/bash
# Checks your Developer ID certificate and App Store Connect API key, then
# uploads them as the GitHub secrets the Release workflow needs.
#
#   scripts/set-release-secrets.sh DeveloperID.p12 AuthKey_ABC123XYZ9.p8 ISSUER_ID [KEY_ID]
#
# KEY_ID defaults to the part of the .p8 file name after "AuthKey_". You're
# asked for the .p12's password. Nothing is printed or written to disk except
# a temporary keychain that's deleted at the end. Needs `gh` signed in with
# access to this repository's secrets.
set -euo pipefail
cd "$(dirname "$0")/.."

usage() { sed -n '2,10p' "$0" | sed 's/^# \{0,1\}//'; exit 1; }
[ $# -ge 3 ] || usage
P12="$1" P8="$2" ISSUER="$3"
KEY_ID="${4:-$(basename "$P8" .p8 | sed -n 's/^AuthKey_//p')}"
[ -f "$P12" ] || { echo "No such file: $P12" >&2; exit 1; }
[ -f "$P8" ] || { echo "No such file: $P8" >&2; exit 1; }
[ -n "$KEY_ID" ] || { echo "Couldn't tell the key ID from \"$P8\"; pass it as the 4th argument" >&2; exit 1; }
command -v gh >/dev/null || { echo "Install the GitHub CLI (gh) first" >&2; exit 1; }
REPO="$(gh repo view --json nameWithOwner -q .nameWithOwner)"

read -r -s -p "Password for $(basename "$P12"): " P12_PASSWORD
echo

# 1. The .p12 holds a Developer ID Application certificate and its private key.
#    Imported into a throwaway keychain, exactly as the workflow does.
KEYCHAIN="$(mktemp -d)/check.keychain-db"
KEYCHAIN_PASSWORD="$(uuidgen)"
cleanup() { security delete-keychain "$KEYCHAIN" 2>/dev/null || true; }
trap cleanup EXIT
security create-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN"
if ! security import "$P12" -k "$KEYCHAIN" -P "$P12_PASSWORD" -T /usr/bin/codesign >/dev/null 2>&1; then
    echo "✗ Couldn't open $(basename "$P12"); is the password right?" >&2
    exit 1
fi
identities="$(security find-identity -v -p codesigning "$KEYCHAIN")"
identity="$(sed -n 's/.*"\(Developer ID Application: .*\)"/\1/p' <<<"$identities" | sed -n 1p)"
if [ -z "$identity" ]; then
    echo "✗ $(basename "$P12") has no \"Developer ID Application\" certificate with its private key." >&2
    echo "  In Keychain Access, select the certificate *and* its key, then File → Export Items as .p12." >&2
    exit 1
fi
echo "✓ Certificate: $identity"

# 2. Apple accepts the API key.
if ! xcrun notarytool history --key "$P8" --key-id "$KEY_ID" --issuer "$ISSUER" >/dev/null 2>&1; then
    echo "✗ Apple didn't accept the API key (key ID $KEY_ID, issuer $ISSUER)." >&2
    echo "  Check the IDs on App Store Connect → Users and Access → Integrations → App Store Connect API." >&2
    exit 1
fi
echo "✓ API key $KEY_ID works for notarization"

# 3. Upload. Values go through stdin, never the command line.
base64 -i "$P12" | gh secret set DEVELOPER_ID_P12 --repo "$REPO"
printf '%s' "$P12_PASSWORD" | gh secret set DEVELOPER_ID_P12_PASSWORD --repo "$REPO"
base64 -i "$P8" | gh secret set NOTARY_KEY_P8 --repo "$REPO"
printf '%s' "$KEY_ID" | gh secret set NOTARY_KEY_ID --repo "$REPO"
printf '%s' "$ISSUER" | gh secret set NOTARY_ISSUER --repo "$REPO"
echo "✓ Secrets set on $REPO. Push a tag, or run the Release workflow by hand for an existing one."
