# BarManager

A small macOS menu bar app that hides the menu bar icons you don't need to see all the time, and shows them again with a click.

- **What it does:** [docs/FEATURES.md](docs/FEATURES.md)
- **What changed:** [CHANGELOG.md](CHANGELOG.md)

Requires macOS 14 or later.

## Install

Download the latest `.dmg` from the GitHub Releases page, open it, and drag BarManager to Applications. The first time you open it, BarManager shows a short how-to.

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
