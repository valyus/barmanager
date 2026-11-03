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
            button.toolTip = "Click to show/hide icons · ⌥-click to show all · Right-click for options"
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
            if Self.mouseIsInMenuBar() {
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
        • Click the arrow to show or hide those icons.
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
