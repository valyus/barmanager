# BarManager

A small macOS menu bar app that hides the menu bar icons you don't need to see all the time, and shows them again with a click.

- **What it does:** [docs/FEATURES.md](docs/FEATURES.md)
- **What changed:** [CHANGELOG.md](CHANGELOG.md)

Requires macOS 14 or later.

## Install

1. Download the latest `.dmg` from the [Releases page](https://github.com/valyus/barmanager/releases).
2. Open it and drag BarManager to Applications.
3. Open BarManager from Applications.

Release builds aren't notarized by Apple yet, so the first time you open BarManager, macOS says it can't check it for malicious software and won't open it. To allow it:

1. Click **Done** (or **OK**) on that message.
2. Open **System Settings → Privacy & Security** and scroll down to Security. Next to the message about BarManager, click **Open Anyway**, then confirm with your password or Touch ID.
3. Open BarManager again and click **Open Anyway** when asked.

You only need to do this once. Or, in Terminal, clear the download flag before opening it:

```bash
xattr -dr com.apple.quarantine /Applications/BarManager.app
```

To check the download, compare its SHA-256 with `SHA256SUMS-x.y.z.txt` from the same release:

```bash
shasum -a 256 ~/Downloads/BarManager-*.dmg
```

The first time you open it, BarManager shows a short how-to.

## Build from source

```bash
scripts/build.sh && open build/BarManager.app
```

`scripts/build.sh` signs with your Developer ID or Apple Development certificate if you have one, so macOS keeps BarManager's permissions across rebuilds. With an ad-hoc signature (`BARMANAGER_SIGN_ID=-`), macOS forgets them after each build. Copy the app to `/Applications` if you want Launch at Login to work reliably.

Run the tests with:

```bash
swift test
```

## Releasing

1. Move the `[Unreleased]` entries in [CHANGELOG.md](CHANGELOG.md) under a new `## [x.y.z] - YYYY-MM-DD` heading.
2. Put the same `x.y.z` in [VERSION](VERSION) and commit.
3. Tag and push: `git tag vx.y.z && git push origin vx.y.z`.

The **Release** workflow then tests, signs with Developer ID, notarizes, and publishes a GitHub release with the `.dmg`, the `.zip` and their checksums, using that version's changelog entry as the notes. It needs these repository secrets:

| Secret | What it is |
|---|---|
| `DEVELOPER_ID_P12` | Your "Developer ID Application" certificate exported as `.p12`, base64-encoded |
| `DEVELOPER_ID_P12_PASSWORD` | The password of that `.p12` |
| `NOTARY_KEY_P8` | An App Store Connect API key (`AuthKey_XXXX.p8`), base64-encoded |
| `NOTARY_KEY_ID` | That key's ID |
| `NOTARY_ISSUER` | Your App Store Connect issuer ID |

To package locally, run `scripts/package.sh` after building. It notarizes too when `NOTARY_KEY_PATH`, `NOTARY_KEY_ID` and `NOTARY_ISSUER` are set.

## Checks

The **CI** workflow runs on every push to `main` and on every pull request: a release build with warnings treated as errors, the tests, an ad-hoc signed app bundle with its `Info.plist` and signature checked, a check that `CHANGELOG.md` has an entry for the current version or `[Unreleased]`, and packaging. The packaged build is attached to the run for 14 days.
