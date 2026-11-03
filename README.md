# BarManager

A tiny macOS menu bar app that hides menu bar icons.

## Build & run

```bash
./build.sh && open build/BarManager.app
```

Copy `build/BarManager.app` to `/Applications` if you want "Launch at Login" to work reliably.

## Use

- **⌘-drag** any menu bar icon to the left of the thin divider `|` to hide it.
- **Click** the arrow to show/hide those icons. They hide again on their own after 10 s (change under right-click → Auto-hide After).
- **⌥-click** the arrow to also reveal the optional "Always Hidden" section (turn it on from the right-click menu, then ⌘-drag icons left of the double divider `‖`).
- **Right-click** the arrow for settings and Quit.

Keep the arrow to the right of the divider. The app refuses to collapse if it isn't, so you can't hide the arrow by accident.

## How it works

The divider is an `NSStatusItem`. To collapse, the app makes it 10,000 pt wide, which pushes every item to its left off the screen. Item positions persist through `autosaveName`.
