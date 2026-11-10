import AppKit
import ServiceManagement

/// Hides menu bar icons using the "expanding item" technique:
///
///   [ always-hidden icons ] ‖ [ hidden icons ] · ‹ [ visible icons ]
///                          ^                  ^ ^
///                 alwaysHiddenItem   hiderItem  toggleItem
///
/// `hiderItem` is invisible and sits right before the arrow. To hide icons it
/// grows to a huge width, which pushes every status item to its left off the
/// screen; to show them it shrinks to zero. (macOS still pads it, so there's a
/// small gap by the arrow; removing the item instead is slow and animated.) (Stretching the arrow itself doesn't work: macOS stops
/// drawing an item that wide.) Users choose what is hidden by ⌘-dragging icons
/// to either side of the arrow.
final class MenuBarController: NSObject, NSMenuDelegate {
    private static let collapsedLength: CGFloat = 10_000
    private static let separatorLength: CGFloat = 8
    private static let toggleLength: CGFloat = 22

    private let toggleItem: NSStatusItem
    /// Invisible; present only while icons are hidden, pushing them off screen.
    private var hiderItem: NSStatusItem?
    /// The hider shrunk to zero while icons are showing, reused to hide them again.
    private var parkedHider: NSStatusItem?
    private let alwaysHiddenItem: NSStatusItem

    private var autoHideTimer: Timer?
    private var showingAlwaysHidden = false

    // Hover
    private let hoverTracker = HoverTracker()
    private var hoverTimer: Timer?
    private var hoverWatchTimer: Timer?

    // Briefly revealing icons that change
    private static let peekDuration: TimeInterval = 5
    private static let peekCooldown: TimeInterval = 20
    private let changeWatcher = ChangeWatcher()
    /// True while the section is open only because an icon changed.
    private var isPeeking = false
    private var lastPeek: [CGWindowID: Date] = [:]

    /// True while at least one section is pushed off screen.
    private var isHidingSomething: Bool {
        isCollapsed
            || (Settings.alwaysHiddenEnabled && alwaysHiddenItem.length == Self.collapsedLength)
    }

    private var isCollapsed: Bool {
        hiderItem != nil
    }

    override init() {
        // On first launch macOS puts new items at the LEFT end of the status
        // area, which on a crowded notched MacBook means behind the notch.
        // Seed preferred positions so the arrow sits next to Control Center,
        // with the double divider just left of it. Later ⌘-drags overwrite these.
        Self.seedPosition(0, for: "BarManager.toggle")
        Self.seedPosition(2, for: "BarManager.alwaysHidden")

        // Items created later are placed further LEFT, so create right-to-left.
        toggleItem = NSStatusBar.system.statusItem(withLength: Self.toggleLength)
        alwaysHiddenItem = NSStatusBar.system.statusItem(withLength: Self.separatorLength)
        super.init()

        // autosaveName makes macOS remember where the user dragged each item.
        toggleItem.autosaveName = "BarManager.toggle"
        alwaysHiddenItem.autosaveName = "BarManager.alwaysHidden"

        // The toggle must never be removable, or the user could lose access.
        toggleItem.behavior = []
        alwaysHiddenItem.behavior = []

        if let button = toggleItem.button {
            button.target = self
            button.action = #selector(toggleClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.toolTip = "Click to show hidden icons · ⌥-click to show all · Right-click for options"
            button.addTrackingArea(NSTrackingArea(
                rect: .zero,
                options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                owner: hoverTracker,
                userInfo: nil
            ))
        }
        hoverTracker.onEnter = { [weak self] in self?.pointerEnteredArrow() }
        hoverTracker.onExit = { [weak self] in self?.hoverTimer?.invalidate() }
        alwaysHiddenItem.button?.image = Self.doubleDividerImage()
        alwaysHiddenItem.button?.toolTip = "Icons left of this line are always hidden (⌥-click the arrow to see them)"
        alwaysHiddenItem.isVisible = Settings.alwaysHiddenEnabled

        changeWatcher.itemsToWatch = { [weak self] in
            guard let self, self.isCollapsed else { return [] }
            return self.hiddenSection().map(\.id)
        }
        changeWatcher.onChange = { [weak self] ids in self?.peek(at: ids) }
        if Settings.showChangedIcons { changeWatcher.start() }

        expand(showAll: false, persist: false)

        // Let the menu bar lay the items out before measuring positions.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            if Settings.isCollapsed { self?.collapse(sound: false) }
        }
    }

    /// Pushes the hidden icons off screen by adding the invisible stretched
    /// item right before the arrow.
    private func stretchHider() {
        guard hiderItem == nil else { return }
        // Reuse the shrunk item: widening it is instant. A fresh one is created only
        // when there's none yet, placed right before the arrow.
        if let parked = parkedHider {
            parkedHider = nil
            parked.length = Self.collapsedLength
            hiderItem = parked
            return
        }
        // Positions count from the right edge, so one point more than the
        // arrow's puts it immediately left of the arrow, past anything dropped there.
        let arrow = UserDefaults.standard.object(forKey: "NSStatusItem Preferred Position BarManager.toggle") as? Double
        UserDefaults.standard.set((arrow ?? 0) + 1, forKey: "NSStatusItem Preferred Position BarManager.hider")
        let item = NSStatusBar.system.statusItem(withLength: Self.collapsedLength)
        item.autosaveName = "BarManager.hider"
        item.behavior = []
        item.button?.setAccessibilityElement(false)
        hiderItem = item
        // Safety net: if it ever lands right of the arrow, it would push the
        // arrow off screen, so take it away and show everything.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            guard let self, let hider = self.hiderItem?.button?.window?.frame,
                  let arrow = self.toggleItem.button?.window?.frame,
                  hider.maxX > arrow.minX + 1 else { return }
            NSLog("BarManager: hider landed right of the arrow; showing icons")
            self.expand(showAll: false)
        }
    }

    /// Shows the hidden icons again by shrinking the item to zero, which macOS
    /// does at once. Removing it instead takes about half a second and then
    /// slides the icons over, so it stays, leaving a small padding gap by the arrow.
    private func removeHider() {
        guard let hider = hiderItem else { return }
        hider.length = 0
        hiderItem = nil
        parkedHider = hider
    }

    private static func seedPosition(_ position: Double, for autosaveName: String) {
        let key = "NSStatusItem Preferred Position \(autosaveName)"
        if UserDefaults.standard.object(forKey: key) == nil {
            UserDefaults.standard.set(position, forKey: key)
        }
    }

    // MARK: - Click handling

    @objc private func toggleClicked(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else { return }
        hoverTimer?.invalidate()
        isPeeking = false // the user took over; use the normal auto-hide
        let isRightClick = event.type == .rightMouseUp || event.modifierFlags.contains(.control)

        if isRightClick {
            showMenu()
        } else if event.modifierFlags.contains(.option) {
            if showingAlwaysHidden {
                collapse()
            } else {
                expand(showAll: true)
                playSound(.expand)
            }
        } else {
            if isCollapsed {
                beginSession(byHover: false)
            } else {
                collapse()
            }
        }
    }

    // MARK: - Expand / collapse

    private func expand(showAll: Bool, persist: Bool = true) {
        removeHider()

        showingAlwaysHidden = showAll && Settings.alwaysHiddenEnabled
        if Settings.alwaysHiddenEnabled {
            if showingAlwaysHidden {
                alwaysHiddenItem.length = Self.separatorLength
                alwaysHiddenItem.button?.image = Self.doubleDividerImage()
            } else {
                hideAlwaysHiddenSection()
            }
        }

        updateToggleIcon()
        if persist { Settings.isCollapsed = false }
        scheduleAutoHide()
    }

    private func collapse(sound: Bool = true) {
        if Settings.alwaysHiddenEnabled { hideAlwaysHiddenSection() }

        // Window IDs can be reused, so look the icons up afresh each time.
        ItemIdentity.forgetCache()
        ItemIdentity.resolve(hiddenSection()) // warm up, so the menu doesn't have to wait
        isPeeking = false
        changeWatcher.rebaseline()
        if sound { playSound(.collapse) }
        autoHideTimer?.invalidate()
        hoverWatchTimer?.invalidate()
        stretchHider()
        showingAlwaysHidden = false
        updateToggleIcon()
        Settings.isCollapsed = true
    }

    private func hideAlwaysHiddenSection() {
        // Only safe while the double divider sits left of the arrow;
        // otherwise it would push the regular hidden section and the arrow away.
        guard alwaysHiddenItem.length == Self.collapsedLength
                || isOrdered(left: alwaysHiddenItem, right: toggleItem) else {
            alwaysHiddenItem.length = Self.separatorLength
            alwaysHiddenItem.button?.image = Self.doubleDividerImage()
            return
        }
        alwaysHiddenItem.button?.image = nil
        alwaysHiddenItem.length = Self.collapsedLength
    }

    private func isOrdered(left: NSStatusItem, right: NSStatusItem) -> Bool {
        guard let l = left.button?.window?.frame, let r = right.button?.window?.frame else {
            return true // can't measure; assume the default creation order
        }
        return l.minX < r.minX
    }

    private func scheduleAutoHide() {
        autoHideTimer?.invalidate()
        let delay = isPeeking ? Self.peekDuration : Settings.autoHideDelay
        guard delay > 0 else { return }
        autoHideTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            guard let self else { return }
            // Don't snap shut while the user is pointing at (or ⌘-dragging in) the menu bar.
            if Self.mouseIsInMenuBar() || MenuBarItemWindow.somethingIsOpen() {
                self.scheduleAutoHide()
            } else if !self.isCollapsed {
                self.collapse()
            }
        }
    }

    private static func mouseIsInMenuBar() -> Bool {
        let mouse = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) }) else { return false }
        let menuBarHeight = screen.frame.maxY - screen.visibleFrame.maxY
        return mouse.y >= screen.frame.maxY - max(menuBarHeight, 24)
    }

    private func updateToggleIcon() {
        let looksOpen = !isCollapsed
        let symbols = Settings.arrowStyle.symbols
        let name = looksOpen ? symbols.expanded : symbols.collapsed
        let config = NSImage.SymbolConfiguration(pointSize: 13, weight: .medium)
        let symbol = NSImage(systemSymbolName: name, accessibilityDescription: looksOpen ? "Hide icons" : "Show hidden icons")?
            .withSymbolConfiguration(config)
        guard let button = toggleItem.button else { return }
        let image = symbol.map { Self.toggleImage(symbol: $0, named: name) }
        image?.isTemplate = true
        image?.accessibilityDescription = symbol?.accessibilityDescription
        button.image = image
        button.title = ""
        button.imagePosition = .imageOnly
        toggleItem.length = Self.toggleLength // fixed, so the arrow never shifts
    }

    // MARK: - Showing icons that change

    /// Opens the hidden section for a few seconds so a changed icon can be seen.
    private func peek(at ids: [CGWindowID]) {
        guard isCollapsed else { return }
        let now = Date()
        let candidates = ids.filter { now.timeIntervalSince(lastPeek[$0] ?? .distantPast) > Self.peekCooldown }
        guard !candidates.isEmpty else { return }
        let windows = MenuBarItemWindow.all().filter { candidates.contains($0.id) }
        ItemIdentity.resolve(windows) { [weak self] identities in
            guard let self, self.isCollapsed else { return }
            let excluded = Settings.neverShowWhenChanged
            guard let id = candidates.first(where: { id in
                identities[id].map { excluded[$0.key] == nil } ?? true
            }) else { return }
            self.lastPeek[id] = Date()
            self.isPeeking = true
            self.beginSession(byHover: false, persist: false)
        }
    }

    // MARK: - Sound

    private enum Cue { case expand, collapse }

    private func playSound(_ cue: Cue) {
        guard let names = Settings.soundTheme.sounds else { return }
        let sound = NSSound(named: cue == .expand ? names.show : names.hide)
        sound?.volume = Settings.soundVolume
        sound?.stop() // restart if it's still playing from a quick double toggle
        sound?.play()
    }

    // MARK: - Hover

    private func pointerEnteredArrow() {
        guard Settings.showOnHover, isCollapsed else { return }
        hoverTimer?.invalidate()
        hoverTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: false) { [weak self] _ in
            guard let self, self.isCollapsed else { return }
            self.beginSession(byHover: true)
        }
    }

    /// Shows the hidden section. With `persist: false` it isn't remembered as
    /// open across launches (used for hover and for briefly showing an icon).
    private func beginSession(byHover: Bool, persist: Bool = true) {
        playSound(.expand)
        expand(showAll: false, persist: persist && !byHover)
        if byHover { startHoverWatch() }
    }

    /// Hides everything again once the pointer has left the menu bar and no menu is open.
    private func startHoverWatch() {
        hoverWatchTimer?.invalidate()
        var lastActive = Date()
        hoverWatchTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] timer in
            guard let self else { return timer.invalidate() }
            if Self.mouseIsInMenuBar() || MenuBarItemWindow.somethingIsOpen() {
                lastActive = Date()
            } else if self.isCollapsed {
                timer.invalidate()
            } else if Date().timeIntervalSince(lastActive) > 0.8 {
                timer.invalidate()
                self.collapse()
            }
        }
    }

    /// Horizontal span of the regular hidden section: right of the "always hidden"
    /// divider (if any) and left of the arrow.
    private struct SectionBounds {
        let minX: CGFloat
        let maxX: CGFloat
    }

    private func sectionBounds() -> SectionBounds {
        // While icons are hidden the stretched item marks the edge; otherwise the arrow does.
        let edge = (hiderItem ?? parkedHider ?? toggleItem).button?.window?.frame
        let doubleDivider = Settings.alwaysHiddenEnabled ? alwaysHiddenItem.button?.window?.frame : nil
        return SectionBounds(minX: doubleDivider?.maxX ?? -.greatestFiniteMagnitude,
                             maxX: edge?.minX ?? -.greatestFiniteMagnitude)
    }

    private static func hiddenSection(_ bounds: SectionBounds) -> [MenuBarItemWindow] {
        MenuBarItemWindow.all().filter { $0.frame.minX >= bounds.minX - 1 && $0.frame.maxX <= bounds.maxX + 1 }
    }

    private func hiddenSection() -> [MenuBarItemWindow] { Self.hiddenSection(sectionBounds()) }

    // MARK: - Menu

    private func showMenu() {
        let menu = NSMenu()
        menu.delegate = self
        addHiddenIconsSection(to: menu)

        let delayMenu = NSMenu()
        for (title, seconds) in [("Never", 0.0), ("5 seconds", 5), ("10 seconds", 10), ("30 seconds", 30), ("1 minute", 60)] {
            let item = NSMenuItem(title: title, action: #selector(setAutoHideDelay(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = seconds
            item.state = Settings.autoHideDelay == seconds ? .on : .off
            delayMenu.addItem(item)
        }
        let delayItem = NSMenuItem(title: "Auto-hide After", action: nil, keyEquivalent: "")
        delayItem.submenu = delayMenu
        menu.addItem(delayItem)

        let hover = NSMenuItem(title: "Show Hidden Icons on Hover", action: #selector(toggleShowOnHover(_:)), keyEquivalent: "")
        hover.target = self
        hover.state = Settings.showOnHover ? .on : .off
        menu.addItem(hover)

        menu.addItem(changedIconsMenuItem())

        let soundMenu = NSMenu()
        for (index, theme) in SoundTheme.allCases.enumerated() {
            if index == 1 { soundMenu.addItem(.separator()) }
            let item = NSMenuItem(title: theme.title, action: #selector(setSoundTheme(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = theme.rawValue
            item.state = Settings.soundTheme == theme ? .on : .off
            soundMenu.addItem(item)
        }
        soundMenu.addItem(.separator())
        soundMenu.addItem(volumeMenuItem())
        let soundItem = NSMenuItem(title: "Sound", action: nil, keyEquivalent: "")
        soundItem.submenu = soundMenu
        menu.addItem(soundItem)

        let arrowMenu = NSMenu()
        for style in ArrowStyle.allCases {
            let item = NSMenuItem(title: style.title, action: #selector(setArrowStyle(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = style.rawValue
            item.state = Settings.arrowStyle == style ? .on : .off
            let preview = NSImage(systemSymbolName: style.symbols.collapsed, accessibilityDescription: nil)
            preview?.isTemplate = true
            item.image = preview
            arrowMenu.addItem(item)
        }
        let arrowItem = NSMenuItem(title: "Arrow Icon", action: nil, keyEquivalent: "")
        arrowItem.submenu = arrowMenu
        menu.addItem(arrowItem)

        let alwaysHidden = NSMenuItem(title: "Enable “Always Hidden” Section", action: #selector(toggleAlwaysHidden(_:)), keyEquivalent: "")
        alwaysHidden.target = self
        alwaysHidden.state = Settings.alwaysHiddenEnabled ? .on : .off
        menu.addItem(alwaysHidden)

        let login = NSMenuItem(title: "Launch at Login", action: #selector(toggleLaunchAtLogin(_:)), keyEquivalent: "")
        login.target = self
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)

        menu.addItem(.separator())
        let help = NSMenuItem(title: "How to Use…", action: #selector(showHelp), keyEquivalent: "")
        help.target = self
        menu.addItem(help)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit BarManager", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        // Attach temporarily so the menu pops up anchored to the status item.
        toggleItem.menu = menu
        toggleItem.button?.performClick(nil)
    }

    func menuDidClose(_ menu: NSMenu) {
        toggleItem.menu = nil // restore normal click handling
    }

    @objc private func setAutoHideDelay(_ sender: NSMenuItem) {
        Settings.autoHideDelay = sender.representedObject as? TimeInterval ?? 10
        if !isCollapsed { scheduleAutoHide() }
    }

    @objc private func toggleShowOnHover(_ sender: NSMenuItem) {
        Settings.showOnHover.toggle()
    }

    @objc private func setSoundTheme(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let theme = SoundTheme(rawValue: raw) else { return }
        Settings.soundTheme = theme
        playSound(.expand) // preview
    }

    /// "Show Icons When They Change" submenu: the on/off switch plus a list of
    /// hidden icons to tick so they never pop up.
    private func changedIconsMenuItem() -> NSMenuItem {
        let submenu = NSMenu()
        let windows = hiddenSection()
        fillChangedIconsMenu(submenu, windows: windows)

        // Never make the menu wait on Accessibility: list what's known now and
        // fill in the rest when the lookup finishes, even while the menu is open.
        if AXIsProcessTrusted(), windows.contains(where: { ItemIdentity.cached($0.id) == nil }) {
            ItemIdentity.resolve(windows) { [weak self, weak submenu] _ in
                guard let self, let submenu else { return }
                submenu.removeAllItems()
                self.fillChangedIconsMenu(submenu, windows: windows)
            }
        }

        let item = NSMenuItem(title: "Show Icons When They Change", action: nil, keyEquivalent: "")
        item.submenu = submenu
        return item
    }

    private func fillChangedIconsMenu(_ submenu: NSMenu, windows: [MenuBarItemWindow]) {
        let toggle = NSMenuItem(title: "Briefly Show Hidden Icons That Change", action: #selector(toggleShowChangedIcons(_:)), keyEquivalent: "")
        toggle.target = self
        toggle.state = Settings.showChangedIcons ? .on : .off
        toggle.toolTip = "When a hidden icon changes (a new badge, a different state), show it for 5 seconds"
        submenu.addItem(toggle)

        if Settings.showChangedIcons, !ChangeWatcher.hasPermission {
            let warning = NSMenuItem(title: "Needs Screen Recording Permission…", action: #selector(openScreenRecordingSettings), keyEquivalent: "")
            warning.target = self
            submenu.addItem(warning)
        }

        submenu.addItem(.separator())
        submenu.addItem(.sectionHeader(title: "Never Show These"))

        // Icons hidden right now, plus anything excluded earlier that isn't.
        let excluded = Settings.neverShowWhenChanged
        var listed = Set<String>()
        var unidentified = 0
        for window in windows {
            guard let identity = ItemIdentity.cached(window.id) else { unidentified += 1; continue }
            guard listed.insert(identity.key).inserted else { continue }
            let image = changeWatcher.snapshots[window.id] ?? identity.appIcon
            submenu.addItem(exclusionItem(key: identity.key, name: identity.name, image: image, isExcluded: excluded[identity.key] != nil))
        }
        for (key, name) in excluded.sorted(by: { $0.value < $1.value }) where !listed.contains(key) {
            submenu.addItem(exclusionItem(key: key, name: name, image: nil, isExcluded: true))
        }

        if unidentified > 0, !AXIsProcessTrusted() {
            let note = NSMenuItem(title: "Allow Accessibility to List Icons…", action: #selector(requestAccessibility), keyEquivalent: "")
            note.target = self
            submenu.addItem(note)
        } else if unidentified > 0 {
            let finding = NSMenuItem(title: "Finding Icons…", action: nil, keyEquivalent: "")
            finding.isEnabled = false
            submenu.addItem(finding)
        } else if windows.isEmpty, excluded.isEmpty {
            let empty = NSMenuItem(title: "No Hidden Icons", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            submenu.addItem(empty)
        }
    }

    private func exclusionItem(key: String, name: String, image: NSImage?, isExcluded: Bool) -> NSMenuItem {
        let item = NSMenuItem(title: name, action: #selector(toggleNeverShow(_:)), keyEquivalent: "")
        item.target = self
        item.representedObject = [key, name]
        item.state = isExcluded ? .on : .off
        item.image = image.map(Self.menuIcon)
        return item
    }

    /// Fits an icon (a menu bar snapshot or an app icon) into a menu row.
    private static func menuIcon(_ image: NSImage) -> NSImage {
        let height: CGFloat = 16
        let width = min(image.size.width * height / max(image.size.height, 1), 40)
        return NSImage(size: NSSize(width: width, height: height), flipped: false) { rect in
            image.draw(in: rect)
            return true
        }
    }

    // MARK: - Hidden icons list

    private static let changeMemory: TimeInterval = 60 * 60
    private static let relativeTime: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter
    }()

    /// Lists the icons in the hidden section at the top of the menu, recently
    /// changed ones first. Choosing one shows it.
    private func addHiddenIconsSection(to menu: NSMenu) {
        let windows = hiddenSection()
        guard !windows.isEmpty else { return }
        let now = Date()
        let changed = changeWatcher.lastChanged.filter { now.timeIntervalSince($0.value) < Self.changeMemory }

        // Nearest the divider first (as they'd appear), recently changed on top.
        let ordered = Array(windows.reversed().enumerated()).sorted { a, b in
            let ta = changed[a.element.id] ?? .distantPast, tb = changed[b.element.id] ?? .distantPast
            return ta != tb ? ta > tb : a.offset < b.offset
        }.map(\.element)

        let title = changed.isEmpty ? "Hidden Icons" : "Hidden Icons · \(changed.count) Changed"
        menu.addItem(.sectionHeader(title: title))
        var items: [CGWindowID: NSMenuItem] = [:]
        for window in ordered {
            let item = NSMenuItem(title: "", action: #selector(showHiddenIcon(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = NSNumber(value: window.id)
            describe(item, window: window, changedAt: changed[window.id])
            menu.addItem(item)
            items[window.id] = item
        }
        menu.addItem(.separator())

        // Names come from Accessibility; fill them in when ready, menu open or not.
        if AXIsProcessTrusted(), windows.contains(where: { ItemIdentity.cached($0.id) == nil }) {
            ItemIdentity.resolve(windows) { [weak self] _ in
                for window in windows {
                    guard let item = items[window.id] else { continue }
                    self?.describe(item, window: window, changedAt: changed[window.id])
                }
            }
        }
    }

    private func describe(_ item: NSMenuItem, window: MenuBarItemWindow, changedAt: Date?) {
        let identity = ItemIdentity.cached(window.id)
        let name = identity?.name ?? "Hidden Icon"
        if let changedAt {
            let note = "Changed \(Self.relativeTime.localizedString(for: changedAt, relativeTo: Date()))"
            if #available(macOS 14.4, *) {
                item.title = name
                item.subtitle = note
            } else {
                item.title = "\(name) — \(note)"
            }
            item.badge = NSMenuItemBadge(string: "New")
        } else {
            item.title = name
        }
        item.toolTip = "Show this icon"
        item.image = (changeWatcher.snapshots[window.id] ?? identity?.appIcon).map(Self.menuIcon)
    }

    @objc private func showHiddenIcon(_ sender: NSMenuItem) {
        guard let id = (sender.representedObject as? NSNumber).map({ CGWindowID($0.uint32Value) }) else { return }
        changeWatcher.markSeen(id)
        isPeeking = false
        if isCollapsed { beginSession(byHover: false, persist: false) }
    }

    @objc private func toggleShowChangedIcons(_ sender: NSMenuItem) {
        Settings.showChangedIcons.toggle()
        if Settings.showChangedIcons {
            if !ChangeWatcher.hasPermission { ChangeWatcher.requestPermission() }
            if !AXIsProcessTrusted() { requestAccessibility() }
            changeWatcher.start()
        } else {
            changeWatcher.stop()
        }
    }

    @objc private func toggleNeverShow(_ sender: NSMenuItem) {
        guard let pair = sender.representedObject as? [String], pair.count == 2 else { return }
        var excluded = Settings.neverShowWhenChanged
        if excluded[pair[0]] == nil { excluded[pair[0]] = pair[1] } else { excluded[pair[0]] = nil }
        Settings.neverShowWhenChanged = excluded
    }

    @objc private func openScreenRecordingSettings() {
        ChangeWatcher.requestPermission()
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    /// A "Volume" label with a slider, embedded in the Sound submenu.
    private func volumeMenuItem() -> NSMenuItem {
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 200, height: 44))

        let label = NSTextField(labelWithString: "Volume")
        label.font = .menuFont(ofSize: 0)
        label.textColor = .secondaryLabelColor
        label.frame = NSRect(x: 14, y: 24, width: 172, height: 16)
        view.addSubview(label)

        let low = NSImageView(image: NSImage(systemSymbolName: "speaker.fill", accessibilityDescription: nil)!)
        low.contentTintColor = .secondaryLabelColor
        low.frame = NSRect(x: 12, y: 4, width: 14, height: 16)
        view.addSubview(low)

        let slider = NSSlider(value: Double(Settings.soundVolume), minValue: 0.05, maxValue: 1,
                              target: self, action: #selector(volumeChanged(_:)))
        slider.isContinuous = false // fire once on release, then preview
        slider.controlSize = .small
        slider.frame = NSRect(x: 30, y: 2, width: 136, height: 20)
        slider.setAccessibilityLabel("Sound volume")
        view.addSubview(slider)

        let high = NSImageView(image: NSImage(systemSymbolName: "speaker.wave.3.fill", accessibilityDescription: nil)!)
        high.contentTintColor = .secondaryLabelColor
        high.frame = NSRect(x: 170, y: 4, width: 20, height: 16)
        view.addSubview(high)

        let item = NSMenuItem()
        item.view = view
        return item
    }

    @objc private func volumeChanged(_ sender: NSSlider) {
        Settings.soundVolume = sender.floatValue
        playSound(.expand) // preview at the new level
    }

    @objc private func setArrowStyle(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let style = ArrowStyle(rawValue: raw) else { return }
        Settings.arrowStyle = style
        updateToggleIcon()
    }

    @objc private func toggleAlwaysHidden(_ sender: NSMenuItem) {
        Settings.alwaysHiddenEnabled.toggle()
        alwaysHiddenItem.isVisible = Settings.alwaysHiddenEnabled
        // Show the double divider so the user can drag icons past it.
        expand(showAll: true)
    }

    @objc private func toggleLaunchAtLogin(_ sender: NSMenuItem) {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            let alert = NSAlert()
            alert.messageText = "Couldn’t change Launch at Login"
            alert.informativeText = "\(error.localizedDescription)\n\nMake sure BarManager.app is in your Applications folder."
            NSApp.activate(ignoringOtherApps: true)
            alert.runModal()
        }
    }

    @objc private func showHelp() { Self.showHowTo() }

    @objc private func quit() { NSApp.terminate(nil) }

    /// Called as the app quits: restore normal widths so nothing stays pushed off screen.
    func prepareForTermination() {
        removeHider()
        parkedHider.map(NSStatusBar.system.removeStatusItem)
        parkedHider = nil
        alwaysHiddenItem.length = Self.separatorLength
    }

    // MARK: - Alerts

    static func showHowTo() {
        let alert = NSAlert()
        alert.messageText = "How to use BarManager"
        alert.informativeText = """
        BarManager adds an arrow ( ‹ ) to your menu bar.

        • Hold ⌘ and drag any menu bar icon to the LEFT of the arrow to hide it, or to its RIGHT to keep it visible.
        • Click the arrow to show those icons. Right-click it to see a list of them, with any that changed recently on top.
        • They also hide on their own after a few seconds (right-click → Auto-hide After).
        • Optionally, a hidden icon that changes (say, gets a badge) shows for 5 seconds. Turn it on, and pick icons that never show, under right-click → Show Icons When They Change.
        • ⌥-click the arrow to also reveal the “Always Hidden” section (enable it from the right-click menu, then ⌘-drag icons left of the double divider ‖).
        • Right-click the arrow for settings and Quit.
        """
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    // MARK: - Drawing

    /// The arrow symbol on a fixed-size canvas, so the arrow never shifts
    /// when the style or state changes.
    private static func toggleImage(symbol: NSImage, named name: String) -> NSImage {
        let canvas = NSSize(width: toggleLength - 2, height: 18)
        // The symbol always sits in the same box in the middle, scaled down if needed.
        let box = NSRect(x: (canvas.width - 13) / 2, y: 2, width: 13, height: 14)
        let scale = min(1, box.width / max(symbol.size.width, 1), box.height / max(symbol.size.height, 1))
        let symbolSize = NSSize(width: symbol.size.width * scale, height: symbol.size.height * scale)
        // Center the visible shape, not the symbol's padded image: ‹ and › are
        // padded on opposite sides, so centering the images makes the arrow jump.
        let ink = inkBounds(of: symbol, named: name)
        let symbolRect = NSRect(x: box.midX - ink.midX * scale, y: box.midY - ink.midY * scale,
                                width: symbolSize.width, height: symbolSize.height)
        return NSImage(size: canvas, flipped: false) { _ in
            symbol.draw(in: symbolRect)
            return true
        }
    }

    private static var inkCache: [String: NSRect] = [:]

    /// The part of `image` that actually has paint in it, in image points.
    private static func inkBounds(of image: NSImage, named name: String) -> NSRect {
        if let cached = inkCache[name] { return cached }
        let scale: CGFloat = 4
        let width = max(Int(image.size.width * scale), 1), height = max(Int(image.size.height * scale), 1)
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        var bounds = NSRect(origin: .zero, size: image.size)
        pixels.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                          bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
                  let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        var minX = width, maxX = -1, minY = height, maxY = -1
        for row in 0..<height {
            for column in 0..<width where pixels[(row * width + column) * 4 + 3] > 25 {
                minX = min(minX, column); maxX = max(maxX, column)
                minY = min(minY, row); maxY = max(maxY, row)
            }
        }
        if maxX >= 0 {
            // Bitmap rows run top to bottom; flip to AppKit's bottom-up y.
            bounds = NSRect(x: CGFloat(minX) / scale, y: CGFloat(height - 1 - maxY) / scale,
                            width: CGFloat(maxX - minX + 1) / scale, height: CGFloat(maxY - minY + 1) / scale)
        }
        inkCache[name] = bounds
        return bounds
    }

    /// The double divider ‖ that marks the "Always Hidden" section.
    private static func doubleDividerImage() -> NSImage {
        let size = NSSize(width: separatorLength, height: 16)
        let image = NSImage(size: size, flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(rect: NSRect(x: rect.midX - 2, y: 1, width: 1, height: 14)).fill()
            NSBezierPath(rect: NSRect(x: rect.midX + 1, y: 1, width: 1, height: 14)).fill()
            return true
        }
        image.isTemplate = true
        return image
    }
}
