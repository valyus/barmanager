import AppKit
import ServiceManagement

/// Hides menu bar icons using the "expanding separator" technique:
///
///   [ always-hidden icons ] ‖ [ hidden icons ] | [ visible icons ] ‹
///                          ^                  ^                   ^
///                 alwaysHiddenItem      separatorItem         toggleItem
///
/// When collapsed, `separatorItem` grows to a huge width, which pushes every
/// status item to its left off the screen. Users choose what is hidden by
/// ⌘-dragging icons to either side of the separator.
final class MenuBarController: NSObject, NSMenuDelegate {
    private static let collapsedLength: CGFloat = 10_000
    private static let separatorLength: CGFloat = 8
    private static let toggleLength: CGFloat = 28

    private let toggleItem: NSStatusItem
    private let separatorItem: NSStatusItem
    private let alwaysHiddenItem: NSStatusItem

    private var autoHideTimer: Timer?
    private var showingAlwaysHidden = false

    // Hover & paging
    private let hoverTracker = HoverTracker()
    private var hoverTimer: Timer?
    private var hoverWatchTimer: Timer?
    private var scrollMonitor: Any?
    private var scrollAccumulator: CGFloat = 0
    private var lastPageChange = Date.distantPast

    /// Hidden-section order (left to right) when the current session began.
    private var baseline: [CGWindowID] = []
    /// Pages of `baseline`, nearest the divider first; each page left to right.
    private var pages: [[CGWindowID]] = []
    private var pageIndex = 0
    /// How many items currently sit rotated from the near end to the far end.
    private var rotation = 0
    private var isMoving = false

    // Briefly revealing icons that change
    private static let peekDuration: TimeInterval = 5
    private static let peekCooldown: TimeInterval = 20
    private let changeWatcher = ChangeWatcher()
    /// True while the section is open only because an icon changed.
    private var isPeeking = false
    private var lastPeek: [CGWindowID: Date] = [:]

    /// True while at least one section is pushed off screen.
    private var isHidingSomething: Bool {
        separatorItem.length != Self.separatorLength
            || (Settings.alwaysHiddenEnabled && alwaysHiddenItem.length == Self.collapsedLength)
    }

    private var isCollapsed: Bool {
        separatorItem.length == Self.collapsedLength
    }

    override init() {
        // On first launch macOS puts new items at the LEFT end of the status
        // area, which on a crowded notched MacBook means behind the notch.
        // Seed preferred positions so the arrow sits next to Control Center,
        // with the dividers just left of it. Later ⌘-drags overwrite these.
        Self.seedPosition(0, for: "BarManager.toggle")
        Self.seedPosition(1, for: "BarManager.separator")
        Self.seedPosition(2, for: "BarManager.alwaysHidden")

        // Items created later are placed further LEFT, so create right-to-left.
        toggleItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        separatorItem = NSStatusBar.system.statusItem(withLength: Self.separatorLength)
        alwaysHiddenItem = NSStatusBar.system.statusItem(withLength: Self.separatorLength)
        super.init()

        // autosaveName makes macOS remember where the user dragged each item.
        toggleItem.autosaveName = "BarManager.toggle"
        separatorItem.autosaveName = "BarManager.separator"
        alwaysHiddenItem.autosaveName = "BarManager.alwaysHidden"

        // The toggle must never be removable, or the user could lose access.
        toggleItem.behavior = []
        separatorItem.behavior = []
        alwaysHiddenItem.behavior = []

        if let button = toggleItem.button {
            button.target = self
            button.action = #selector(toggleClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.toolTip = "Click to show hidden icons · Click or scroll for the next page · ⌥-click to show all · Right-click for options"
            button.addTrackingArea(NSTrackingArea(
                rect: .zero,
                options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                owner: hoverTracker,
                userInfo: nil
            ))
        }
        hoverTracker.onEnter = { [weak self] in self?.pointerEnteredArrow() }
        hoverTracker.onExit = { [weak self] in self?.hoverTimer?.invalidate() }
        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            self?.handleScroll(event)
            return event
        }
        separatorItem.button?.image = Self.separatorImage(double: false)
        separatorItem.button?.toolTip = "Icons left of this line are hidden"
        alwaysHiddenItem.button?.image = Self.separatorImage(double: true)
        alwaysHiddenItem.button?.toolTip = "Icons left of this line are always hidden (⌥-click the arrow to see them)"
        alwaysHiddenItem.isVisible = Settings.alwaysHiddenEnabled

        changeWatcher.itemsToWatch = { [weak self] in
            guard let self, self.isCollapsed, !self.isMoving else { return [] }
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
            } else if !showingAlwaysHidden, pageIndex < pages.count - 1 {
                showPage(pageIndex + 1)
            } else {
                collapse()
            }
        }
    }

    // MARK: - Expand / collapse

    private func expand(showAll: Bool, persist: Bool = true) {
        separatorItem.length = Self.separatorLength
        separatorItem.button?.image = Self.separatorImage(double: false)

        showingAlwaysHidden = showAll && Settings.alwaysHiddenEnabled
        if Settings.alwaysHiddenEnabled {
            if showingAlwaysHidden {
                alwaysHiddenItem.length = Self.separatorLength
                alwaysHiddenItem.button?.image = Self.separatorImage(double: true)
            } else {
                hideAlwaysHiddenSection()
            }
        }

        updateToggleIcon()
        if persist { Settings.isCollapsed = false }
        scheduleAutoHide()
    }

    private func collapse(sound: Bool = true) {
        // Never collapse if the separator ended up to the right of the toggle —
        // that would push the toggle itself off screen and lock the user out.
        guard isOrdered(left: separatorItem, right: toggleItem) else {
            NSSound.beep()
            Self.showMisorderedAlert()
            return
        }
        if Settings.alwaysHiddenEnabled { hideAlwaysHiddenSection() }

        if !isMoving {
            let items = hiddenSection()
            // Window IDs can be reused, so look the icons up afresh each time.
            ItemIdentity.forgetCache()
            ItemIdentity.resolve(items) // warm up, so the menu doesn't have to wait
        }
        isPeeking = false
        changeWatcher.rebaseline()
        if sound { playSound(.collapse) }
        autoHideTimer?.invalidate()
        hoverWatchTimer?.invalidate()
        separatorItem.button?.image = nil
        separatorItem.length = Self.collapsedLength
        showingAlwaysHidden = false
        pages = []
        pageIndex = 0
        updateToggleIcon()
        Settings.isCollapsed = true
        restoreOrderWhenHidden()
    }

    private func hideAlwaysHiddenSection() {
        // Only safe while the double divider sits left of the normal one;
        // otherwise it would push the regular hidden section and divider away.
        guard alwaysHiddenItem.length == Self.collapsedLength
                || isOrdered(left: alwaysHiddenItem, right: separatorItem) else {
            alwaysHiddenItem.length = Self.separatorLength
            alwaysHiddenItem.button?.image = Self.separatorImage(double: true)
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
            if self.isMoving || Self.mouseIsInMenuBar() || MenuBarItemWindow.somethingIsOpen() {
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
        // Mid page change the section is briefly pushed away; keep showing the open state.
        let looksOpen = !isCollapsed || isMoving
        let symbols = Settings.arrowStyle.symbols
        let name = looksOpen ? symbols.expanded : symbols.collapsed
        let config = NSImage.SymbolConfiguration(pointSize: 13, weight: .medium)
        let symbol = NSImage(systemSymbolName: name, accessibilityDescription: looksOpen ? "Hide icons" : "Show hidden icons")?
            .withSymbolConfiguration(config)
        guard let button = toggleItem.button else { return }

        // While paging, a small raised label at the arrow's top right: "2/3".
        let paging = looksOpen && !showingAlwaysHidden && pages.count > 1
        let label: String?
        let spoken: String?
        if paging {
            label = "\(pageIndex + 1)/\(pages.count)"
            spoken = "Page \(pageIndex + 1) of \(pages.count)"
        } else {
            label = nil
            spoken = nil
        }
        let image = symbol.map { Self.toggleImage(symbol: $0, named: name, superscript: label) }
        image?.isTemplate = true
        image?.accessibilityDescription = spoken ?? symbol?.accessibilityDescription
        button.image = image
        button.title = ""
        button.imagePosition = .imageOnly
        toggleItem.length = Self.toggleLength // fixed, so the arrow never shifts
    }

    // MARK: - Showing icons that change

    /// Opens the hidden section for a few seconds so a changed icon can be seen.
    private func peek(at ids: [CGWindowID]) {
        guard isCollapsed, !isMoving else { return }
        let now = Date()
        let candidates = ids.filter { now.timeIntervalSince(lastPeek[$0] ?? .distantPast) > Self.peekCooldown }
        guard !candidates.isEmpty else { return }
        let windows = MenuBarItemWindow.all().filter { candidates.contains($0.id) }
        ItemIdentity.resolve(windows) { [weak self] identities in
            guard let self, self.isCollapsed, !self.isMoving else { return }
            let excluded = Settings.neverShowWhenChanged
            guard let id = candidates.first(where: { id in
                identities[id].map { excluded[$0.key] == nil } ?? true
            }) else { return }
            self.lastPeek[id] = Date()
            self.isPeeking = true
            self.beginSession(byHover: false, peekAt: id)
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

    // MARK: - Hover & paging

    private func pointerEnteredArrow() {
        guard Settings.showOnHover, isCollapsed, !isMoving else { return }
        hoverTimer?.invalidate()
        hoverTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: false) { [weak self] _ in
            guard let self, self.isCollapsed else { return }
            self.beginSession(byHover: true)
        }
    }

    /// Shows the hidden section, split into pages that each fit on screen.
    /// With `peekAt`, opens the page holding that item, without remembering the
    /// section as open.
    private func beginSession(byHover: Bool, peekAt: CGWindowID? = nil) {
        guard !isMoving else { return }
        if rotation == 0 {
            let items = hiddenSection()
            baseline = items.map(\.id)
            pages = makePages(items)
        } else {
            pages = makePages(baselineItems())
        }
        pageIndex = 0
        if pages.count > 1, !ItemMover.hasPermission {
            ItemMover.requestPermission() // paging needs Accessibility
            pages = []
        }

        playSound(.expand)
        let startPage = peekAt.flatMap { id in pages.firstIndex { $0.contains(id) } } ?? 0
        if rotation == 0, startPage == 0 {
            expand(showAll: false, persist: !byHover && peekAt == nil)
        } else {
            showPage(startPage) // also finishes a previous restore that didn't
        }
        if byHover { startHoverWatch() }
    }

    /// Hides everything again once the pointer has left the menu bar and no menu is open.
    private func startHoverWatch() {
        hoverWatchTimer?.invalidate()
        var lastActive = Date()
        hoverWatchTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] timer in
            guard let self else { return timer.invalidate() }
            if self.isMoving || Self.mouseIsInMenuBar() || MenuBarItemWindow.somethingIsOpen() {
                lastActive = Date()
            } else if self.isCollapsed {
                timer.invalidate()
            } else if Date().timeIntervalSince(lastActive) > 0.8 {
                timer.invalidate()
                self.collapse()
            }
        }
    }

    private func handleScroll(_ event: NSEvent) {
        guard event.window != nil, event.window === toggleItem.button?.window,
              !isCollapsed, !isMoving, pages.count > 1, event.momentumPhase.isEmpty,
              Date().timeIntervalSince(lastPageChange) > 0.4 else { return }
        let delta = abs(event.scrollingDeltaY) > abs(event.scrollingDeltaX) ? event.scrollingDeltaY : -event.scrollingDeltaX
        scrollAccumulator += event.hasPreciseScrollingDeltas ? delta : delta * 10
        guard abs(scrollAccumulator) > 20 else { return }
        let step = scrollAccumulator < 0 ? 1 : -1
        scrollAccumulator = 0
        showPage((pageIndex + step + pages.count) % pages.count)
    }

    /// Rotates the hidden items so page `index` sits next to the divider.
    /// The shuffle happens while the section is pushed off screen.
    private func showPage(_ index: Int) {
        guard !isMoving else { return }
        let target = pages.prefix(index).reduce(0) { $0 + $1.count }
        lastPageChange = Date()
        pageIndex = index

        if target == rotation {
            expand(showAll: false, persist: false)
            return
        }
        isMoving = true
        autoHideTimer?.invalidate()
        separatorItem.button?.image = nil
        separatorItem.length = Self.collapsedLength
        updateToggleIcon()
        rotate(to: target) { [weak self] in
            guard let self else { return }
            self.isMoving = false
            self.expand(showAll: false, persist: false)
        }
    }

    /// Puts the original order back after a session that changed pages.
    private func restoreOrderWhenHidden() {
        guard rotation != 0, !isMoving else { return }
        isMoving = true
        rotate(to: 0) { [weak self] in self?.isMoving = false }
    }

    /// Rotates the hidden section until `target` items have moved from the near end
    /// of `baseline` to its far end, taking whichever direction needs fewer moves.
    private func rotate(to target: Int, completion: @escaping () -> Void) {
        // Let the menu bar finish laying out the collapsed section first.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            guard let self else { return completion() }
            let bounds = self.sectionBounds()
            let baseline = self.baseline
            let current = self.rotation
            ItemMover.queue.async {
                let n = baseline.count
                var achieved: Int? = current
                if n > 1 {
                    let forward = ((target - current) % n + n) % n
                    let ok = forward <= n - forward
                        ? Self.rotateForward(forward, bounds: bounds)
                        : Self.rotateBack(n - forward, bounds: bounds)
                    let order = Self.hiddenSection(bounds).map(\.id)
                    let expected = Array(baseline.suffix(target) + baseline.prefix(n - target))
                    if ok, order == expected {
                        achieved = target
                    } else {
                        NSLog("BarManager: hidden icons ended up out of order; keeping the new order")
                        achieved = nil
                    }
                }
                let order = Self.hiddenSection(bounds)
                DispatchQueue.main.async {
                    if let achieved {
                        self.rotation = achieved
                    } else {
                        // Something moved unexpectedly. Treat the current order as the original.
                        self.baseline = order.map(\.id)
                        self.rotation = 0
                        self.pages = self.makePages(order)
                        self.pageIndex = 0
                    }
                    completion()
                }
            }
        }
    }

    /// Moves the `count` items nearest the divider to the far end, keeping their order.
    private static func rotateForward(_ count: Int, bounds: SectionBounds) -> Bool {
        guard count > 0 else { return true }
        let items = hiddenSection(bounds)
        guard count < items.count, let farthest = items.first else { return false }
        var anchor = farthest.id
        var first = true
        var ok = true
        ItemMover.batch {
            for id in items.suffix(count).map(\.id) {
                let fresh = hiddenSection(bounds)
                guard let item = fresh.first(where: { $0.id == id }),
                      let target = fresh.first(where: { $0.id == anchor }),
                      ItemMover.move(item, to: first ? .leftOf(target) : .rightOf(target)) else { ok = false; return }
                anchor = id
                first = false
            }
        }
        return ok
    }

    /// Moves the `count` items at the far end back next to the divider, keeping their order.
    private static func rotateBack(_ count: Int, bounds: SectionBounds) -> Bool {
        guard count > 0 else { return true }
        let items = hiddenSection(bounds)
        guard count < items.count else { return false }
        var ok = true
        ItemMover.batch {
            for id in items.prefix(count).map(\.id) {
                let fresh = hiddenSection(bounds)
                guard let item = fresh.first(where: { $0.id == id }), let nearest = fresh.last,
                      ItemMover.move(item, to: .rightOf(nearest)) else { ok = false; return }
            }
        }
        return ok
    }

    /// Horizontal span of the regular hidden section: right of the "always hidden"
    /// divider (if any) and left of the normal divider.
    private struct SectionBounds {
        let minX: CGFloat
        let maxX: CGFloat
    }

    private func sectionBounds() -> SectionBounds {
        let separator = separatorItem.button?.window?.frame
        let doubleDivider = Settings.alwaysHiddenEnabled ? alwaysHiddenItem.button?.window?.frame : nil
        return SectionBounds(minX: doubleDivider?.maxX ?? -.greatestFiniteMagnitude,
                             maxX: separator?.minX ?? -.greatestFiniteMagnitude)
    }

    private static func hiddenSection(_ bounds: SectionBounds) -> [MenuBarItemWindow] {
        MenuBarItemWindow.all().filter { $0.frame.minX >= bounds.minX - 1 && $0.frame.maxX <= bounds.maxX + 1 }
    }

    private func hiddenSection() -> [MenuBarItemWindow] { Self.hiddenSection(sectionBounds()) }

    private func baselineItems() -> [MenuBarItemWindow] {
        let byID = Dictionary(hiddenSection().map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        return baseline.compactMap { byID[$0] }
    }

    /// Splits items (left to right) into pages that fit between the notch, or a
    /// strip kept free for app menus on other screens, and the divider. Nearest page first.
    private func makePages(_ items: [MenuBarItemWindow]) -> [[CGWindowID]] {
        guard let separator = separatorItem.button?.window?.frame,
              let screen = separatorItem.button?.window?.screen ?? NSScreen.main else { return [] }
        let visibleLeft = screen.auxiliaryTopRightArea?.minX ?? (screen.frame.minX + 400)
        // Leave room for the divider and the page indicator next to the arrow.
        let available = max(separator.maxX - Self.separatorLength - 40 - visibleLeft, 80)

        var pages: [[CGWindowID]] = []
        var page: [CGWindowID] = []
        var width: CGFloat = 0
        for item in items.reversed() {
            if !page.isEmpty, width + item.frame.width > available {
                pages.append(page)
                page = []
                width = 0
            }
            page.insert(item.id, at: 0)
            width += item.frame.width
        }
        if !page.isEmpty { pages.append(page) }
        return pages
    }

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
        if isCollapsed {
            beginSession(byHover: false, peekAt: id)
        } else if let page = pages.firstIndex(where: { $0.contains(id) }), page != pageIndex {
            showPage(page)
        }
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
        // Show the new separator so the user can drag icons past it.
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

    /// Called as the app quits: put the hidden icons back in their original
    /// order and restore normal widths so nothing stays pushed off screen.
    func prepareForTermination() {
        if rotation != 0, !isMoving {
            separatorItem.length = Self.collapsedLength
            var done = false
            rotate(to: 0) { done = true }
            let deadline = Date().addingTimeInterval(5)
            while !done, Date() < deadline {
                RunLoop.current.run(until: Date().addingTimeInterval(0.05))
            }
        }
        separatorItem.length = Self.separatorLength
        alwaysHiddenItem.length = Self.separatorLength
    }

    // MARK: - Alerts

    static func showHowTo() {
        let alert = NSAlert()
        alert.messageText = "How to use BarManager"
        alert.informativeText = """
        BarManager adds an arrow ( ‹ ) and a thin divider ( | ) to your menu bar.

        • Hold ⌘ and drag any menu bar icon to the LEFT of the divider to hide it.
        • Click the arrow to show those icons. Right-click it to see a list of them, with any that changed recently on top.
        • If they don’t all fit, click again (or scroll over the arrow) for the next page. Clicking on the last page hides them.
        • They also hide on their own after a few seconds (right-click → Auto-hide After).
        • Optionally, a hidden icon that changes (say, gets a badge) shows for 5 seconds. Turn it on, and pick icons that never show, under right-click → Show Icons When They Change.
        • ⌥-click the arrow to also reveal the “Always Hidden” section (enable it from the right-click menu, then ⌘-drag icons left of the double divider ‖).
        • Right-click the arrow for settings and Quit.

        Keep the arrow to the RIGHT of the divider.
        """
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    static func showMisorderedAlert() {
        let alert = NSAlert()
        alert.messageText = "Divider is on the wrong side"
        alert.informativeText = "The divider ( | ) must be to the LEFT of the arrow. ⌘-drag it back to the left of the arrow, then try again."
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    // MARK: - Drawing

    /// The arrow symbol on a fixed-size canvas, optionally with a small label
    /// raised at its top right. The size never changes, so the arrow doesn't
    /// shift when the number comes and goes or gets more digits.
    private static func toggleImage(symbol: NSImage, named name: String, superscript: String?) -> NSImage {
        let canvas = NSSize(width: toggleLength - 2, height: 18)
        // The symbol always sits in the same box on the left, scaled down if needed;
        // the label gets the top-right corner, wide enough for "2/3".
        let box = NSRect(x: 1, y: 2, width: 13, height: 14)
        let scale = min(1, box.width / max(symbol.size.width, 1), box.height / max(symbol.size.height, 1))
        let symbolSize = NSSize(width: symbol.size.width * scale, height: symbol.size.height * scale)
        // Center the visible shape, not the symbol's padded image: ‹ and › are
        // padded on opposite sides, so centering the images makes the arrow jump.
        let ink = inkBounds(of: symbol, named: name)
        let symbolRect = NSRect(x: box.midX - ink.midX * scale, y: box.midY - ink.midY * scale,
                                width: symbolSize.width, height: symbolSize.height)

        let text = superscript.map {
            NSAttributedString(string: $0, attributes: [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 8, weight: .bold),
                .foregroundColor: NSColor.black,
            ])
        }
        return NSImage(size: canvas, flipped: false) { _ in
            symbol.draw(in: symbolRect)
            if let text {
                let size = text.size()
                text.draw(at: NSPoint(x: canvas.width - size.width, y: canvas.height - size.height + 1))
            }
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

    private static func separatorImage(double: Bool) -> NSImage {
        let size = NSSize(width: separatorLength, height: 16)
        let image = NSImage(size: size, flipped: false) { rect in
            NSColor.black.setFill()
            if double {
                NSBezierPath(rect: NSRect(x: rect.midX - 2, y: 1, width: 1, height: 14)).fill()
                NSBezierPath(rect: NSRect(x: rect.midX + 1, y: 1, width: 1, height: 14)).fill()
            } else {
                NSBezierPath(rect: NSRect(x: rect.midX - 0.5, y: 1, width: 1, height: 14)).fill()
            }
            return true
        }
        image.isTemplate = true
        return image
    }
}
