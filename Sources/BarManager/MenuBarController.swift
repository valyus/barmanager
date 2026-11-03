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

    // Hover panel
    private let panel = HiddenItemsPanel()
    private let hoverTracker = HoverTracker()
    private var hoverTimer: Timer?
    private var panelWatchTimer: Timer?
    private var pointerLeftPanelAt: Date?
    private var imageCache: [CGWindowID: NSImage] = [:]

    // Temporarily revealing one item that was picked from the panel
    private var revealWatchTimer: Timer?

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
            button.toolTip = "Hover to see hidden icons · Click to show/hide · ⌥-click to show all · Right-click for options"
            button.addTrackingArea(NSTrackingArea(
                rect: .zero,
                options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                owner: hoverTracker,
                userInfo: nil
            ))
        }
        hoverTracker.onEnter = { [weak self] in self?.pointerEnteredArrow() }
        hoverTracker.onExit = { [weak self] in self?.hoverTimer?.invalidate() }
        panel.onSelect = { [weak self] item in self?.open(item) }
        panel.onRequestPermission = { [weak self] in self?.requestScreenRecording() }
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
        hidePanel()
        let isRightClick = event.type == .rightMouseUp || event.modifierFlags.contains(.control)

        if isRightClick {
            showMenu()
        } else if event.modifierFlags.contains(.option) {
            if showingAlwaysHidden { collapse() } else { expand(showAll: true) }
        } else {
            if isCollapsed { expand(showAll: false) } else { collapse() }
        }
    }

    // MARK: - Expand / collapse

    private func expand(showAll: Bool, persist: Bool = true) {
        stopRevealWatch()
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

        stopRevealWatch()
        autoHideTimer?.invalidate()
        separatorItem.button?.image = nil
        separatorItem.length = Self.collapsedLength
        showingAlwaysHidden = false
        updateToggleIcon()
        Settings.isCollapsed = true
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
            if Self.mouseIsInMenuBar() || MenuBarItemWindow.somethingIsOpen() || self.panel.isVisible {
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
        toggleItem.button?.image = image
    }

    // MARK: - Hover panel

    private func pointerEnteredArrow() {
        guard Settings.showOnHover, isHidingSomething, !panel.isVisible else { return }
        hoverTimer?.invalidate()
        hoverTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: false) { [weak self] _ in
            self?.showPanel()
        }
    }

    private func showPanel() {
        guard let anchor = toggleItem.button?.window?.frame else { return }
        let items = hiddenItems()
        panel.show(items: items, images: imageCache, below: anchor)
        startPanelWatch()

        let ids = items.map(\.id)
        Task { @MainActor [weak self] in
            let fresh = await ItemCapture.capture(ids)
            guard let self, !fresh.isEmpty else { return }
            self.imageCache.merge(fresh) { _, new in new }
            self.panel.update(images: self.imageCache)
        }
    }

    private func hidePanel() {
        panelWatchTimer?.invalidate()
        panelWatchTimer = nil
        pointerLeftPanelAt = nil
        panel.orderOut(nil)
    }

    /// Closes the panel shortly after the pointer leaves both the arrow and the panel.
    private func startPanelWatch() {
        panelWatchTimer?.invalidate()
        pointerLeftPanelAt = nil
        panelWatchTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self else { return }
            guard let arrow = self.toggleItem.button?.window?.frame else { return self.hidePanel() }
            let zone = arrow.union(self.panel.frame).insetBy(dx: -8, dy: -8)
            if zone.contains(NSEvent.mouseLocation) {
                self.pointerLeftPanelAt = nil
            } else if let left = self.pointerLeftPanelAt {
                if Date().timeIntervalSince(left) > 0.3 { self.hidePanel() }
            } else {
                self.pointerLeftPanelAt = Date()
            }
        }
    }

    /// Every status item currently left of our divider(s), left to right.
    private func hiddenItems() -> [MenuBarItemWindow] {
        guard let separator = separatorItem.button?.window?.frame else { return [] }
        let ownDivider = alwaysHiddenItem.isVisible ? alwaysHiddenItem.button?.window?.frame : nil
        return MenuBarItemWindow.all().filter { item in
            guard item.frame.maxX <= separator.minX + 1 else { return false }
            if let ownDivider, abs(ownDivider.minX - item.frame.minX) < 1, abs(ownDivider.width - item.frame.width) < 1 {
                return false
            }
            return true
        }
    }

    /// Slides the hidden section just far enough that `item` is on screen, then clicks it.
    private func open(_ item: MenuBarItemWindow) {
        hidePanel()
        guard let separator = separatorItem.button?.window?.frame else { return }
        let screen = separatorItem.button?.window?.screen ?? NSScreen.main

        // Distance from the item's left edge to the divider. It doesn't change
        // when the divider's width does, so we can work out where the item lands.
        var distance = separator.minX - item.frame.minX
        if Settings.alwaysHiddenEnabled, alwaysHiddenItem.length == Self.collapsedLength,
           let doubleDivider = alwaysHiddenItem.button?.window?.frame,
           item.frame.maxX <= doubleDivider.minX + 1 {
            distance -= doubleDivider.width - Self.separatorLength
            alwaysHiddenItem.length = Self.separatorLength
            alwaysHiddenItem.button?.image = Self.separatorImage(double: true)
            showingAlwaysHidden = true
        }

        // Land the item just right of the notch (or the screen's left edge).
        let visibleLeft = (screen?.auxiliaryTopRightArea?.minX ?? screen?.frame.minX ?? 0) + 12
        let length = max(Self.separatorLength, separator.maxX - distance - visibleLeft)

        autoHideTimer?.invalidate()
        separatorItem.button?.image = length > Self.separatorLength ? nil : Self.separatorImage(double: false)
        separatorItem.length = length
        updateToggleIcon()

        // Give the menu bar a moment to lay out before clicking.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            guard let self else { return }
            if let moved = MenuBarItemWindow.all().first(where: { $0.id == item.id }) {
                Self.click(at: CGPoint(x: moved.frame.midX, y: moved.frame.midY))
            }
            self.startRevealWatch()
        }
    }

    private static func click(at point: CGPoint) {
        guard CGPreflightPostEventAccess() else {
            // Ask once; until it's granted the item is just revealed for a manual click.
            CGRequestPostEventAccess()
            return
        }
        let original = CGEvent(source: nil)?.location
        let source = CGEventSource(stateID: .hidSystemState)
        CGEvent(mouseEventSource: source, mouseType: .leftMouseDown, mouseCursorPosition: point, mouseButton: .left)?
            .post(tap: .cghidEventTap)
        CGEvent(mouseEventSource: source, mouseType: .leftMouseUp, mouseCursorPosition: point, mouseButton: .left)?
            .post(tap: .cghidEventTap)
        if let original { CGWarpMouseCursorPosition(original) }
    }

    /// Hides the revealed item again once its menu closes and the pointer leaves the menu bar.
    private func startRevealWatch() {
        stopRevealWatch()
        let started = Date()
        revealWatchTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self else { return }
            if Date().timeIntervalSince(started) < 1.5 { return }
            if Self.mouseIsInMenuBar() || MenuBarItemWindow.somethingIsOpen() || self.panel.isVisible { return }
            self.stopRevealWatch()
            self.collapse()
        }
    }

    private func stopRevealWatch() {
        revealWatchTimer?.invalidate()
        revealWatchTimer = nil
    }

    private func requestScreenRecording() {
        hidePanel()
        if !CGRequestScreenCaptureAccess(),
           let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
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

    @objc private func quit() {
        // Restore normal widths so nothing stays pushed off-screen after quitting.
        separatorItem.length = Self.separatorLength
        alwaysHiddenItem.length = Self.separatorLength
        NSApp.terminate(nil)
    }

    // MARK: - Alerts

    static func showHowTo() {
        let alert = NSAlert()
        alert.messageText = "How to use BarManager"
        alert.informativeText = """
        BarManager adds an arrow ( ‹ ) and a thin divider ( | ) to your menu bar.

        • Hold ⌘ and drag any menu bar icon to the LEFT of the divider to hide it.
        • Hover over the arrow to see all hidden icons in a panel; click one to open it.
        • Click the arrow to show or hide those icons in the menu bar.
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
