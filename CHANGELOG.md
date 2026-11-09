# Changelog

All notable changes to BarManager are listed here, newest first. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow [Semantic Versioning](https://semver.org/).

New changes go under **[Unreleased]** as they're made. When releasing, that section becomes the new version.

## [Unreleased]

### Added
- A list of the hidden icons at the top of the right-click menu, with each icon's picture and app name. Choose one to show it. Icons that changed in the last hour come first, marked **New** with when they changed.
- **Show Icons When They Change** (off by default): a hidden icon whose picture changes is shown for 5 s. Includes a **Never Show These** list for icons that change all the time.
- **Sound** when icons show and hide, with 7 sound sets plus None, and a **Volume** slider.
- **Arrow Icon** styles: Chevron, Triangle, Arrow, Circle, Dots and Eye.
- Release tooling: versioned builds from `VERSION`, hardened-runtime signing, `scripts/package.sh` for a `.dmg` and `.zip` with optional notarization, a CI workflow for every push and pull request, and a Release workflow for tags.
- Unit tests for the sound sets and arrow styles.
- [docs/FEATURES.md](docs/FEATURES.md), describing every feature.

### Changed
- Clicking the arrow shows hidden icons. Hovering is now off by default; turn it back on under right-click → Show Hidden Icons on Hover.
- The page label, like `2/3`, is drawn small at the arrow's top right instead of beside it.
- The arrow always keeps the same size and position, so it and the icons next to it no longer shift when it changes.
- `build.sh` moved to `scripts/build.sh`.

### Fixed
- The right-click menu no longer pauses while BarManager looks up which app owns each icon.

## [1.0.0] - 2026-11-04

### Added
- Hide menu bar icons by ⌘-dragging them left of a divider; click or hover over the arrow to show them.
- Pages for hidden icons that don't fit next to the notch, with click or scroll to move between them.
- An optional Always Hidden section, shown with ⌥-click.
- Auto-hide after a delay, Launch at Login, and a first-run how-to.
