# BarManager

macOS menu bar app (Swift Package, AppKit, macOS 14+) that hides menu bar icons.

## Keep the docs live

Every change that someone using the app could notice, including new features, changed behavior, fixes, new settings and new permissions, must update, in the same change:

1. **CHANGELOG.md**: add a line under `## [Unreleased]` in the right group (Added / Changed / Fixed / Removed). Write it for people who use the app, not in code terms.
2. **docs/FEATURES.md**: update the section the change touches so it still describes the app exactly as it behaves.
3. The in-app help text (`showHowTo()` in `MenuBarController.swift`) if the basics of using it changed.

Internal-only changes (refactors, CI) go in the changelog only if they affect how the app is built or released.

## Build & check

```bash
swift build -c release -Xswiftc -warnings-as-errors
swift test
scripts/build.sh && open build/BarManager.app
```

CI (`.github/workflows/ci.yml`) runs the same plus packaging. Releases: see README → Releasing.
