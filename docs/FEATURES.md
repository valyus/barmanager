# BarManager features

BarManager adds an **arrow** to the right side of your menu bar. Icons to the left of the arrow are hidden; icons to its right stay visible.

```
[ always-hidden icons ] ‖ [ hidden icons ] ‹ [ visible icons ]
```

## Hiding icons

- **⌘-drag** any menu bar icon to the left of the arrow to hide it, or to its right to keep it visible. This is the standard macOS way to rearrange menu bar icons; BarManager remembers where everything goes.

## Showing hidden icons

- **Click** the arrow to show the hidden icons. They're the real icons, not copies, so they work as usual.
- **Click** again to hide them. They also hide on their own after 10 s. Change that under right-click → **Auto-hide After** (5 s, 10 s, 30 s, 1 minute or Never). They stay open while the pointer is in the menu bar or one of their menus is open.
- **Hover instead of click:** turn on right-click → **Show Hidden Icons on Hover**. Then pointing at the arrow shows them, and moving away hides them.

### When they don't all fit

All hidden icons show at once. If there isn't room for them, for example next to the notch or a long row of app menus, macOS doesn't draw the ones farthest from the arrow. Either show them in the [bar below the menu bar](#bar-below-the-menu-bar), or ⌘-drag the icons you need most close to the arrow and move ones you rarely need to the [Always Hidden section](#always-hidden-section).

## Bar below the menu bar

Hidden icons can show in a strip just below the menu bar instead of in the menu bar itself, so the notch and app menus never cover them.

- Choose under Settings → General → **Show hidden icons**:
  - **In the Menu Bar** (default): as described above.
  - **In a Bar Below the Menu Bar**: clicking the arrow always opens the bar.
  - **In the Menu Bar, or Below It When They Don't Fit**: the bar opens only when the hidden icons are wider than the room between the arrow and the notch (or the front app's menus).
- **Click** an icon in the bar to open it: BarManager shows the hidden icons in the menu bar and opens that icon's menu. ⌥-click the arrow to include the Always Hidden section.
- Clicking anywhere else, or the arrow again, closes the bar.
- The bar shows each icon's real picture with **Screen Recording** permission, otherwise its app's icon. It needs **Accessibility**; without it, the arrow shows icons in the menu bar as usual.

## Search

Find any menu bar icon by name and open it, wherever it is.

- Right-click the arrow → **Search Icons…**, or set a shortcut under Settings → Shortcuts.
- Type part of a name ("wi" finds Wi‑Fi, "cc" finds Control Center). Use ↑ and ↓ to pick, Return to open, Esc to close.
- Each result shows which section the icon is in. Opening a hidden icon shows its section first, then opens its menu.
- Needs **Accessibility** permission.

## Keyboard shortcuts

Shortcuts work in any app. Set them under Settings → **Shortcuts**: click the button, then press the keys. They need ⌘, ⌥ or ⌃ (F-keys work alone). Esc cancels, Delete removes the shortcut. A shortcut can do only one thing; giving it to a second action takes it from the first.

- **Show or hide hidden icons**: same as clicking the arrow.
- **Show all, including "Always Hidden"**: same as ⌥-clicking it.
- **Search menu bar icons.**
- **Open one icon**: under Settings → Icons, give any icon a shortcut that opens its menu, hidden or not.
- **Switch profile**: under Settings → Profiles.

Shortcuts need no permission, except opening an icon, which needs **Accessibility**.

## Always Hidden section

An optional second section for icons you almost never need.

- Turn it on with right-click → **Enable "Always Hidden" Section**. A double divider `‖` appears; ⌘-drag icons to its left. Keep it left of the arrow; if it ends up on the right, BarManager leaves that section showing rather than hide the arrow.
- **⌥-click** the arrow to show this section too. A normal click never shows it.

## Hidden icons list

Right-click the arrow to see a list of the icons in the hidden section, at the top of the menu, each with its picture and app name.

- Choose one to show the hidden icons right away. If they don't all fit, the one you chose may still be out of sight.
- If **Show Icons When They Change** is on, icons that changed in the last hour are listed first, marked **New** and with when they changed, like "Changed 3 min ago". The heading says how many changed. Choosing an icon clears its mark.
- App names need **Accessibility** permission. Without it, icons are listed as "Hidden Icon".

## Show icons when they change

Off by default. When it's on and a hidden icon's picture changes, say it gets a badge or switches state, BarManager shows the hidden icons for 5 s, then hides them again. An icon that doesn't fit stays out of sight.

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

The arrow takes a narrow 22 pt spot, always keeps the same size and sits centered in it, whatever its state or style, so the icons next to it never shift.

## Profiles

A profile is a saved set of settings to switch between, like Work, Home or Presenting.

- It covers: whether icons are hidden, auto-hide, hover, showing icons that change, sound, arrow style, where hidden icons show, and the menu bar tint and border. Which icons are in which section stays as it is.
- **Save:** right-click → **Profile** → **Save Current Settings as Profile…**, or Settings → Profiles → **Save Current Settings as Profile**.
- **Switch:** right-click → **Profile** and choose one, press its shortcut, or let a [trigger](#triggers) switch it. The current one has a checkmark; changing a setting afterwards removes the checkmark until settings match a profile again.
- **Presenting:** Settings → Profiles → **Add "Presenting" Profile** adds one that hides everything, including the Always Hidden section, with no sounds and no icons popping up when they change.
- In Settings → Profiles, rename a profile, give it a shortcut, **Apply** it, or under ⋯ **Update with Current Settings** or **Delete** it. Deleting one also removes its shortcut and the triggers that switch to it.

## Triggers

Triggers act on their own when something happens. Add them under Settings → **Triggers**.

| When | |
|---|---|
| Battery is below a level | 5% to 95% |
| Running on battery | |
| An external display is connected | |
| An app is open | chosen from the apps running now |
| An app is in front | |
| During certain hours | can run past midnight, like 22:00 to 07:00 |
| The network changes | Wi‑Fi, cable or VPN connects or disconnects |

Then either:

- **Show hidden icons.** For a lasting condition, they stay open while it's true and the normal auto-hide takes over when it ends. For a network change, they show and then hide after the usual auto-hide delay.
- **Switch to a profile** when the condition starts.

Switch each trigger on or off, or delete it, in the list. Conditions are checked every 10 seconds and whenever apps or displays change.

## Appearance

Under Settings → **Appearance**:

- **Arrow icon:** the same choices as right-click → Arrow Icon.
- **Tint the menu bar** with a color and strength, and/or a **line under the menu bar**. Both stay out of the way of clicks and hide when an app goes full screen.
- **Spacers:** up to 5 blank items with a faint dot. A new one appears just right of the arrow; ⌘-drag it between icons to group them.
- **Space between icons:** Standard, Compact, Tight or Roomy. This is a macOS-wide setting that each app reads when it starts, so log out and back in to see it everywhere. Standard puts back the macOS default.

## Settings window

Right-click the arrow → **Settings…** opens a window with everything in one place:

- **General:** where hidden icons show, auto-hide, hover, showing icons that change, Always Hidden, sound and volume, Launch at Login, and which permissions are allowed.
- **Shortcuts**, **Profiles**, **Triggers** and **Appearance**, as described above.
- **Icons:** every menu bar icon, nearest the arrow first, with its section (Visible, Hidden, Always Hidden), a **Never pop up** switch (the same list as Show Icons When They Change → Never Show These) and a shortcut that opens it. To move an icon to another section, ⌘-drag it in the menu bar. Needs **Accessibility**.
- **Backup:** **Export Settings…** saves every setting, profile, trigger and shortcut, plus where BarManager's own items sit, to a `.plist` file. **Import Settings…** replaces the current settings with a file's; positions of BarManager's own items apply the next time it starts. **Reset All Settings…** goes back to defaults, deleting profiles, triggers and shortcuts.

## Other settings

Right-click the arrow for:

- **Search Icons…** and **Profile**, near the top.
- **Launch at Login.** Works best when BarManager is in your Applications folder.
- **Settings…**: the [settings window](#settings-window).
- **How to Use…**: the short guide that also appears the first time you open BarManager.
- **Quit BarManager.** Quitting shows every hidden icon again.

## Permissions

| Permission | Needed for | Without it |
|---|---|---|
| **Accessibility** | App names in the lists, search, shortcuts for single icons, the bar below the menu bar, the Icons tab | Icons listed without names; search and the bar ask for it; the arrow shows icons in the menu bar |
| **Screen Recording** | Show icons when they change (a small snapshot of each hidden icon every 2 s), real pictures in the bar below the menu bar | That feature stays inactive; the bar shows app icons |

macOS asks for each one the first time it's needed. Snapshots stay in memory only; nothing is saved or sent anywhere. After granting Screen Recording you may need to quit and reopen BarManager.

## How it works

To hide icons, BarManager adds an invisible, empty menu bar item right before the arrow and makes it 10,000 pt wide, which pushes every item to its left off the screen while the arrow stays put. To show them, it shrinks that item to zero so they appear at once. macOS still gives the item a little padding, so there's a small gap between the icons and the arrow while they're showing. Item positions are remembered by macOS.

If hiding would ever push the arrow itself off screen, BarManager shows the icons instead.

Opening an icon (from search, the bar or a shortcut) asks it through Accessibility to act as if clicked. Icons that don't respond to that get a real click at their position, and the pointer goes back where it was.

On macOS 27 the window server no longer lists each menu bar item as a window of its own. When BarManager sees that, it reads positions through Accessibility instead, so the hidden icons list, search and the bar keep working with Accessibility permission. Showing icons when they change needs per-item windows, so it stays inactive there. This fallback hasn't been tested on macOS 27 yet.

On macOS 26 every menu bar icon belongs to Control Center as far as the window list is concerned, so BarManager finds out which app owns each icon by matching positions with each app's menu bar items through Accessibility.
