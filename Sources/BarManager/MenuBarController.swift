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
            button.toolTip = "Hover to show hidden icons · Click or scroll for the next page · ⌥-click to show all · Right-click for options"
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

        expand(showAll: false, persist: false)

        // Let the menu bar lay the items out before measuring positions.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            if Settings.isCollapsed { self?.collapse() }
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
        let isRightClick = event.type == .rightMouseUp || event.modifierFlags.contains(.control)

        if isRightClick {
            showMenu()
        } else if event.modifierFlags.contains(.option) {
            if showingAlwaysHidden { collapse() } else { expand(showAll: true) }
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

    private func collapse() {
        // Never collapse if the separator ended up to the right of the toggle —
        // that would push the toggle itself off screen and lock the user out.
        guard isOrdered(left: separatorItem, right: toggleItem) else {
            NSSound.beep()
            Self.showMisorderedAlert()
            return
        }
        if Settings.alwaysHiddenEnabled { hideAlwaysHiddenSection() }

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
        let delay = Settings.autoHideDelay
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
        let name = isCollapsed ? "chevron.left" : "chevron.right"
        let image = NSImage(systemSymbolName: name, accessibilityDescription: isCollapsed ? "Show hidden icons" : "Hide icons")
        image?.isTemplate = true
        guard let button = toggleItem.button else { return }
        button.image = image

        // Page indicator, e.g. "2/3", while there's more than one page.
        let paging = !isCollapsed && !showingAlwaysHidden && pages.count > 1
        if paging {
            button.attributedTitle = NSAttributedString(
                string: "\(pageIndex + 1)/\(pages.count)",
                attributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium)]
            )
            button.imagePosition = .imageTrailing
            toggleItem.length = NSStatusItem.variableLength
        } else {
            button.title = ""
            button.imagePosition = .imageOnly
            toggleItem.length = NSStatusItem.squareLength
        }
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
    private func beginSession(byHover: Bool) {
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

        if rotation == 0 {
            expand(showAll: false, persist: !byHover)
        } else {
            showPage(0) // a previous restore didn't finish
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
        • Hover over the arrow to show those icons. If they don’t all fit, click the arrow (or scroll over it) for the next page.
        • Move the pointer away and they hide again.
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
