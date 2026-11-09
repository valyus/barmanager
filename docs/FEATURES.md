# BarManager features

BarManager adds two things to the right side of your menu bar: an **arrow** and a thin **divider** `|`. Icons to the left of the divider are hidden; icons to its right stay visible.

```
[ always-hidden icons ] ‖ [ hidden icons ] | [ visible icons ] ‹
```

## Hiding icons

- **⌘-drag** any menu bar icon to the left of the divider `|` to hide it, or to the right to keep it visible. This is the standard macOS way to rearrange menu bar icons; BarManager remembers where everything goes.
- Keep the arrow to the right of the divider. If they end up the wrong way round, BarManager refuses to hide anything (so it can't hide its own arrow) and tells you how to fix it.

## Showing hidden icons

- **Click** the arrow to show the hidden icons. They're the real icons, not copies, so they work as usual.
- **Click** again to hide them. They also hide on their own after 10 s. Change that under right-click → **Auto-hide After** (5 s, 10 s, 30 s, 1 minute or Never). They stay open while the pointer is in the menu bar or one of their menus is open.
- **Hover instead of click:** turn on right-click → **Show Hidden Icons on Hover**. Then pointing at the arrow shows them, and moving away hides them.

## Pages

If the hidden icons don't all fit, for example next to the notch, BarManager splits them into pages.

- The arrow shows which page you're on as a small label at its top right, like `1/3`.
- **Click** the arrow or **scroll** over it for the next page. Clicking on the last page hides them.
- When the icons hide again, or when you quit, BarManager puts them back in your original order.
- Paging needs **Accessibility** permission (see [Permissions](#permissions)). Without it you still get the first page.

## Always Hidden section

An optional second section for icons you almost never need.

- Turn it on with right-click → **Enable "Always Hidden" Section**. A double divider `‖` appears; ⌘-drag icons to its left.
- **⌥-click** the arrow to show this section too. A normal click never shows it.

## Hidden icons list

Right-click the arrow to see a list of the icons in the hidden section, at the top of the menu, each with its picture and app name.

- Choose one to show it right away, jumping to its page if there are several.
- If **Show Icons When They Change** is on, icons that changed in the last hour are listed first, marked **New** and with when they changed, like "Changed 3 min ago". The heading says how many changed. Choosing an icon clears its mark.
- App names need **Accessibility** permission. Without it, icons are listed as "Hidden Icon".

## Show icons when they change

Off by default. When it's on and a hidden icon's picture changes, say it gets a badge or switches state, BarManager shows that icon's page for 5 s, then hides it again.

- Turn it on under right-click → **Show Icons When They Change** → **Briefly Show Hidden Icons That Change**.
- Point at the menu bar during those 5 s to keep it open, or click the arrow to keep it open normally.
- **Never show some icons:** in the same submenu, under **Never Show These**, tick icons that should never pop up, like a clock or a CPU meter that changes all the time. Icons you ticked stay listed even when they aren't hidden, so you can untick them later.
- The same icon waits at least 20 s before it can pop up again.
- If most icons change at once, that's the menu bar's look changing (dark mode, wallpaper tint), so nothing pops up.
- Icons in the Always Hidden section never pop up.
- Needs **Screen Recording** permission, and **Accessibility** for the Never Show list (see [Permissions](#permissions)).

## Sound

A soft sound plays when the icons show and when they hide. It doesn't play when BarManager starts.

- Choose under right-click → **Sound**:

  | Choice | Show | Hide |
  |---|---|---|
  | None | – | – |
  | Pop (default) | Pop | Tink |
  | Bubble | Bottle | Pop |
  | Glass | Glass | Ping |
  | Morse | Morse | Morse |
  | Purr | Purr | Funk |
  | Submarine | Submarine | Blow |
  | Frog | Frog | Hero |

- Picking a sound plays it so you can hear it first.
- **Volume:** the slider at the bottom of the Sound menu, 5% to 100% of your Mac's volume (35% to start). Letting go of it plays the sound at the new level.

## Arrow icon

Choose the arrow's look under right-click → **Arrow Icon**: Chevron (default), Triangle, Arrow, Circle, Dots or Eye. Each has a picture in the menu and changes right away.

The arrow always keeps the same size and position, whatever its state, style or label, so the icons next to it never shift.

## Other settings

Right-click the arrow for:

- **Launch at Login.** Works best when BarManager is in your Applications folder.
- **How to Use…**: the short guide that also appears the first time you open BarManager.
- **Quit BarManager.** Quitting shows every hidden icon again and puts them back in order.

## Permissions

| Permission | Needed for | Without it |
|---|---|---|
| **Accessibility** | Pages (BarManager moves icons with simulated ⌘-drags) and app names in the lists | Only the first page; icons listed without names |
| **Screen Recording** | Show icons when they change (a small snapshot of each hidden icon every 2 s) | That feature stays inactive |

macOS asks for each one the first time it's needed. Snapshots stay in memory only; nothing is saved or sent anywhere. After granting Screen Recording you may need to quit and reopen BarManager.

## How it works

The divider is a regular menu bar item. To hide icons, BarManager makes it 10,000 pt wide, which pushes every item to its left off the screen. Item positions are remembered by macOS.

To show another page, BarManager pushes the hidden section off screen, moves the next page's icons next to the divider using ⌘-drags aimed at each icon's window, then brings the section back.

On macOS 26 every menu bar icon belongs to Control Center as far as the window list is concerned, so BarManager finds out which app owns each icon by matching positions with each app's menu bar items through Accessibility.
