# BarManager

A tiny macOS menu bar app that hides menu bar icons.

## Build & run

```bash
./build.sh && open build/BarManager.app
```

Copy `build/BarManager.app` to `/Applications` if you want "Launch at Login" to work reliably.

## Use

- **⌘-drag** any menu bar icon to the left of the thin divider `|` to hide it.
- **Hover** over the arrow to see every hidden icon in a panel below it, wrapped into rows so long lists still fit. Click an icon there to open it: the bar slides just far enough to show that item, clicks it, then hides it again when you're done.
- **Click** the arrow to show/hide those icons. They hide again on their own after 10 s (change under right-click → Auto-hide After).
- **⌥-click** the arrow to also reveal the optional "Always Hidden" section (turn it on from the right-click menu, then ⌘-drag icons left of the double divider `‖`).
- **Right-click** the arrow for settings and Quit.

Keep the arrow to the right of the divider. The app refuses to collapse if it isn't, so you can't hide the arrow by accident.

## Permissions

The hover panel works without permissions, but it's more useful with two:

- **Screen Recording** shows the real icons in the panel instead of placeholders. Use the link at the bottom of the panel.
- **Accessibility** lets a click in the panel open the item's menu for you. Without it the item is only revealed, and you click it yourself. macOS asks the first time you click an icon in the panel.

`build.sh` signs the app ad hoc, so macOS may forget these grants after each rebuild. Turn the toggles off and on again in System Settings if that happens.

## How it works

The divider is an `NSStatusItem`. To collapse, the app makes it 10,000 pt wide, which pushes every item to its left off the screen. Item positions persist through `autosaveName`.
