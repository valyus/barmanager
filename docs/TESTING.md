# Manual test checklist

Run through this before each release. Tick boxes as you go; each item says what should happen. Items marked **⚠︎** are the ones most likely to be wrong, because they were never checked by hand when written.

Written for 1.1.0. When a feature changes, update its section here along with [FEATURES.md](FEATURES.md).

## Setup

- [ ] Quit any other copy of BarManager (they share settings and would both add an arrow).
- [ ] Build and open the release build: `scripts/build.sh && open build/BarManager.app`.
- [ ] Note your macOS version and Mac (notch or not, number of displays): ____________
- [ ] Right-click the arrow → **Settings…** → General → **Permissions**. Allow **Accessibility** and **Screen Recording**, then quit and reopen BarManager. Both rows show **Allowed**.
- [ ] Optional, for a first-run check: Backup → **Export Settings…** first, then `defaults delete com.ovalius.barmanager` and reopen. The how-to appears once. Import your export afterwards.

## Basics (unchanged in 1.1.0, check nothing regressed)

- [ ] ⌘-drag an icon left of the arrow: it hides when the icons hide. ⌘-drag it right of the arrow: it stays visible.
- [ ] Click the arrow: hidden icons appear at once and work. Click again: they hide. A sound plays each way.
- [ ] Leave them open: they hide after 10 s. While the pointer is in the menu bar or a menu is open, they stay.
- [ ] Right-click the arrow: the hidden icons list is at the top, with pictures and app names.
- [ ] Turn on the Always Hidden section, ⌘-drag an icon left of `‖`. A normal click doesn't show it; ⌥-click does.
- [ ] Quit BarManager: every hidden icon comes back.

## Search

- [ ] Right-click → **Search Icons…**: a search box opens near the top of the screen with the cursor in it, and the app you were in stays in front.
- [ ] It lists every menu bar icon, each with its section (Visible, Hidden, Always Hidden).
- [ ] Type `wi`: Wi‑Fi comes first. Type `cc`: Control Center items appear.
- [ ] **⚠︎** ↓ and ↑ move the highlight through the results and the list scrolls to it. (Single-line text fields can swallow arrow keys.)
- [ ] Return on a **visible** icon: its menu opens right away.
- [ ] Return on a **hidden** icon: the hidden icons show, then its menu opens under it.
- [ ] Return on an **Always Hidden** icon: that section shows too, then its menu opens.
- [ ] Clicking a result does the same as Return.
- [ ] Esc closes the box. Clicking another app also closes it.
- [ ] With Accessibility turned off: Search asks for it instead of opening an empty box.

## Opening icons (applies to search, the bar and icon shortcuts)

- [ ] Try at least five different apps' icons, including one from Control Center (Wi‑Fi, Battery) and one third-party app. Each opens its menu or popover.
- [ ] **⚠︎** If an icon doesn't respond to being opened through Accessibility, BarManager clicks it instead. The pointer should end up back where it was. Note any icon that opens nothing or opens in the wrong place: ____________

## Keyboard shortcuts

In Settings → **Shortcuts**:

- [ ] Click **Record Shortcut**, press ⌃⌥⌘H: the button shows `⌃⌥⌘H`.
- [ ] While recording, a plain letter only beeps; Esc cancels; Delete removes the shortcut.
- [ ] In another app, ⌃⌥⌘H shows the hidden icons; again hides them.
- [ ] **Show all** shortcut shows Always Hidden too, like ⌥-click.
- [ ] **Search** shortcut opens the search box from any app, including with the settings window closed.
- [ ] Give the same keys to a second action: the first loses them.
- [ ] Quit and reopen: shortcuts still work.

## Bar below the menu bar

Settings → General → **Show hidden icons**:

- [ ] **In a Bar Below the Menu Bar**: clicking the arrow opens a strip just under the menu bar, right edge under the arrow, with the hidden icons' real pictures.
- [ ] Without Screen Recording, the strip shows app icons instead.
- [ ] Click an icon in the strip: the strip closes, the icons show in the menu bar, and that icon's menu opens.
- [ ] Clicking elsewhere or the arrow again closes the strip.
- [ ] ⌥-click the arrow: the strip includes Always Hidden icons.
- [ ] **In the Menu Bar, or Below It When They Don't Fit**, on a Mac with a notch: with few hidden icons, clicking shows them in the menu bar. With many (or an app with lots of menus in front, like Xcode), clicking opens the strip instead.
- [ ] **In the Menu Bar**: behaves exactly as before 1.1.0.

## Settings window

- [ ] Right-click → **Settings…** opens it in front; ⌘, in the right-click menu does too. Opening it again brings the same window forward.
- [ ] **General**: every control changes the matching right-click menu item, and the other way round (change the sound in the menu while the window is open; the window updates).
- [ ] **Icons**: lists every icon, nearest the arrow first, grouped Visible, Hidden, Always Hidden. **Reload** updates it after you ⌘-drag something.
- [ ] **Icons → Never pop up** matches right-click → Show Icons When They Change → Never Show These.
- [ ] **Icons → Shortcut**: give one icon a shortcut; it opens that icon's menu from any app, even while hidden.

## Profiles

- [ ] Right-click → **Profile → Save Current Settings as Profile…**, name it "Work": it appears in the menu with a checkmark.
- [ ] Change the arrow style: the checkmark goes away. Change it back: it returns.
- [ ] Settings → Profiles → **Add "Presenting" Profile**, then choose it from the menu: icons hide, Always Hidden hides, no sound plays, and changed icons don't pop up.
- [ ] Switch back to Work: your earlier settings return.
- [ ] Give a profile a shortcut; it switches from any app.
- [ ] Rename a profile in Settings; the menu shows the new name.
- [ ] Delete a profile that a trigger uses: the trigger is deleted too.

## Triggers

In Settings → **Triggers**, add each, then check:

- [ ] **An app is in front** (pick Safari) → Show hidden icons: switching to Safari shows them and they stay; leaving Safari lets them hide after the auto-hide delay.
- [ ] **An app is open** → Switch to Presenting: opening the app switches profile.
- [ ] **The network changes** → Show hidden icons: turn Wi‑Fi off and on; icons show, then hide after the delay. Nothing happens when BarManager starts.
- [ ] **⚠︎** **Connected to a Wi‑Fi network**: click **Use Current**. macOS asks for Location Services once (the prompt explains it's for the Wi‑Fi name); after allowing, the field fills with your network. Add it with Show hidden icons: icons show within 10 s. Join another network or turn Wi‑Fi off: they hide after the delay. Settings → General → Permissions now lists Location Services as Allowed. (Untested whether a hardened, signed build gets the prompt at all.)
- [ ] Deny Location Services (System Settings → Privacy & Security → Location Services): the New trigger section says the trigger can't start, and the trigger does nothing.
- [ ] **During certain hours**, set to a window that includes now: icons show within 10 s.
- [ ] **Running on battery** (laptop): unplug; icons show within 10 s. Plug in; they hide after the delay.
- [ ] **An external display is connected**: plug one in; icons show.
- [ ] Turning a rule's switch off ends it right away; deleting it does too.
- [ ] Clicking the arrow to hide icons while a trigger holds them open hides them.

## Appearance

- [ ] **⚠︎** **Tint the menu bar**: the menu bar takes the color, *behind* the icons and app menus. Menus, icons and clicks all work through it. (Untested which layer it lands on; it might cover icons or not show at all.)
- [ ] Change the color and strength: it updates at once.
- [ ] **Line under the menu bar** shows a thin line.
- [ ] Open a full-screen app: no tint or line over it. Switch back: they return.
- [ ] With two displays: both menu bars are tinted.
- [ ] **⚠︎** **Spacers: 2**: two faint dots appear right of the arrow. (Untested where new ones land; note it: ____________) ⌘-drag them between icons. Spacers in the hidden section don't show up in the hidden icons list or search.
- [ ] Spacers back to 0: they disappear.
- [ ] **Space between icons → Tight**, log out and back in: icons sit closer together. **Standard** puts it back after another log out and in.

## Backup

- [ ] **Export Settings…** saves a `.plist`.
- [ ] Change several settings, then **Import Settings…** that file: they all come back, including profiles, triggers and shortcuts.
- [ ] Importing some other `.plist` says it isn't a BarManager export and changes nothing.
- [ ] **Reset All Settings…** asks first, then returns to defaults; the how-to doesn't appear again.

## Show icons when they change (with the new features)

- [ ] Still works with Screen Recording: a hidden icon that changes shows for 5 s.
- [ ] It doesn't pop up while the search box or the strip is open in a way that fights with them.

## Updates

Needs a release build with `sparkle-public-key.txt` and a published newer version, or a local test feed (see README → Setting up in-app updates).

- [ ] Settings → General → Updates shows the two switches and "Last checked…". A build without the key says it can't update itself and has no **Check for Updates…** menu item.
- [ ] Right-click → **Check for Updates…** with no newer version: Sparkle says you're up to date.
- [ ] With a newer version: the arrow gets a dot, the right-click menu starts with **Install BarManager x.y.z…**, and choosing it shows the release notes and installs; BarManager restarts on the new version with your settings and permissions intact.
- [ ] **Skip This Version** clears the dot and the menu item.
- [ ] With automatic install on: the update downloads by itself and installs when BarManager quits.

## Edge cases

- [ ] Notched MacBook with many icons: the arrow is never pushed behind the notch or off screen, whatever you hide.
- [ ] Two displays: clicking the arrow on either display's menu bar works; the strip opens on the display you clicked.
- [ ] Sleep and wake, and switching Spaces: hidden icons stay hidden; tint stays.
- [ ] Leave it running for an hour with triggers and change alerts on: CPU in Activity Monitor stays near 0%.
- [ ] macOS 27, if available: the hidden icons list, search and the strip still list icons (Accessibility fallback). Note what works: ____________

## Notes

Bugs found, with steps:

-
