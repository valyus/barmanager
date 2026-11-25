# Changelog

All notable changes to BarManager are listed here, newest first. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow [Semantic Versioning](https://semver.org/).

New changes go under **[Unreleased]** as they're made. When releasing, that section becomes the new version.

## [Unreleased]

### Added
- **In-app updates.** BarManager checks for new versions once a day and shows a dot on the arrow and **Install BarManager x.y.z…** at the top of the right-click menu when one is ready. Check by hand with right-click → **Check for Updates…**, or choose automatic checks and installs under Settings → General → Updates. Updates are signed, and BarManager installs only ones signed by its developer. Versions before 1.2.0 can't update themselves, so get this one from GitHub.
- **Move icons from Settings.** In Settings → Icons, choose Visible, Hidden or Always Hidden next to any icon to move it there. BarManager does the ⌘-drag for you, shows every section while it works, puts the pointer back, then hides icons again as before. If an icon is behind the notch or won't move, it says so.
- **Wi‑Fi network trigger**: show hidden icons or switch profiles while you're on a particular Wi‑Fi network, like switching to your Work profile at the office. Type the network's name or click **Use Current**. macOS shares Wi‑Fi names only with apps allowed to use Location Services, so BarManager asks for that the first time you add one. It reads only the network name, never your location.

### Changed
- Releases are now checked end to end: the Release workflow stops early if a signing or notarization secret is missing, signs only with Developer ID, signs the `.dmg` too, and checks that Gatekeeper accepts the build before publishing. It can also be run by hand to replace an existing release's files with notarized ones. `scripts/set-release-secrets.sh` checks and uploads the secrets.

## [1.1.0] - 2026-11-26

### Added
- **Search Icons**: a Spotlight-style box that finds any menu bar icon by name and opens it, even a hidden one. Open it from the right-click menu or with a shortcut.
- **Keyboard shortcuts** that work in any app: show or hide hidden icons, show all including Always Hidden, search, open one particular icon, and switch profiles.
- **A bar below the menu bar** for hidden icons: choose to always show hidden icons there, or only when they wouldn't fit next to the notch or the app's menus. Click an icon in the bar to open it.
- **Settings window** (right-click → Settings…) with General, Shortcuts, Icons, Triggers, Profiles, Appearance and Backup tabs. The Icons tab lists every menu bar icon with its section, a shortcut and a "never pop up" switch.
- **Profiles**: save your settings as Work, Home, Presenting and so on, then switch from the right-click menu, a shortcut or a trigger. Includes a ready-made Presenting profile that hides everything and keeps quiet.
- **Triggers**: show hidden icons or switch profiles on their own while on battery, below a battery level, with an external display, while an app is open or in front, during certain hours, or when the network changes.
- **Menu bar tint and border**, **spacers** to group icons, and a **Space between icons** setting.
- **Export and import** of all settings, plus Reset.
- A list of the hidden icons at the top of the right-click menu, with each icon's picture and app name. Choose one to show it. Icons that changed in the last hour come first, marked **New** with when they changed.
- **Show Icons When They Change** (off by default): a hidden icon whose picture changes is shown for 5 s. Includes a **Never Show These** list for icons that change all the time.
- **Sound** when icons show and hide, with 7 sound sets plus None, and a **Volume** slider.
- **Arrow Icon** styles: Chevron, Triangle, Arrow, Circle, Dots and Eye.
- Release tooling: versioned builds from `VERSION`, hardened-runtime signing, `scripts/package.sh` for a `.dmg` and `.zip` with optional notarization, a CI workflow for every push and pull request, and a Release workflow for tags.
- Unit tests for the sound sets and arrow styles.
- [docs/FEATURES.md](docs/FEATURES.md), describing every feature.

### Changed
- If a menu bar ever lays items out so that hiding would push the arrow off screen, BarManager now shows the icons instead of losing the arrow.
- Where the window server stops listing menu bar items one by one (macOS 27), BarManager finds them through Accessibility instead.
- The thin divider `|` is gone. The arrow itself is now the boundary: icons left of the arrow are hidden, icons right of it stay visible. Icons you kept visible between the old divider and the arrow are now hidden; ⌘-drag them to the right of the arrow to keep them visible.
- Clicking the arrow shows hidden icons. Hovering is now off by default; turn it back on under right-click → Show Hidden Icons on Hover.
- The arrow takes up less room in the menu bar.
- The arrow always keeps the same size and sits centered in its spot, so it and the icons next to it no longer shift when it changes.
- `build.sh` moved to `scripts/build.sh`.

### Fixed
- The right-click menu no longer pauses while BarManager looks up which app owns each icon.

### Removed
- Pages. Clicking or scrolling over the arrow no longer cycles through hidden icons that don't fit. When the arrow is clicked, all hidden icons show at once, and any that don't fit next to the notch or the app's menus stay out of sight. Paging rearranged icons with simulated drags, which made the pointer jump around the screen.

## [1.0.0] - 2026-11-04

### Added
- Hide menu bar icons by ⌘-dragging them left of a divider; click or hover over the arrow to show them.
- Pages for hidden icons that don't fit next to the notch, with click or scroll to move between them.
- An optional Always Hidden section, shown with ⌥-click.
- Auto-hide after a delay, Launch at Login, and a first-run how-to.
