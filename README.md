# BarManager

A tiny macOS menu bar app that hides menu bar icons.

## Build & run

```bash
./build.sh && open build/BarManager.app
```

Copy `build/BarManager.app` to `/Applications` if you want "Launch at Login" to work reliably.

## Use

- **⌘-drag** any menu bar icon to the left of the thin divider `|` to hide it.
- **Hover** over the arrow to show the hidden icons. They're the real icons, so they work as usual. Move the pointer away and they hide again.
- If they don't all fit (say, next to the notch), they're split into pages and the arrow shows which one you're on, like `1/3`. **Click** the arrow or **scroll** over it for the next page. Clicking on the last page hides them.
- If hovering is off (right-click → Show Hidden Icons on Hover), **click** the arrow to show/hide those icons. They hide again on their own after 10 s (change under right-click → Auto-hide After).
- **⌥-click** the arrow to also reveal the optional "Always Hidden" section (turn it on from the right-click menu, then ⌘-drag icons left of the double divider `‖`).
- **Right-click** the arrow for settings and Quit.

Keep the arrow to the right of the divider. The app refuses to collapse if it isn't, so you can't hide the arrow by accident.

## Permissions

Paging needs **Accessibility** permission, because BarManager rearranges your icons with simulated ⌘-drags. macOS asks the first time there's more than one page. Without it you still get the first page.

`build.sh` signs with your Apple Development certificate if you have one, so the permission survives rebuilds. With an ad-hoc signature macOS forgets it after each build.

## How it works

The divider is an `NSStatusItem`. To collapse, the app makes it 10,000 pt wide, which pushes every item to its left off the screen. Item positions persist through `autosaveName`.

To show another page, BarManager pushes the hidden section off screen and moves the next page's icons next to the divider using ⌘-drags aimed at each icon's window, then brings the section back. When the icons hide again (or the app quits), it moves them back into your original order.
