import AppKit

/// One menu bar item as Accessibility sees it: which app owns it, what it's
/// called, where it is, and a handle for opening it.
struct MenuBarEntry {
    /// Stable across launches: the bundle ID, plus the item's label for apps
    /// (like Control Center) that own several items.
    let key: String
    let name: String
    let appIcon: NSImage?
    let pid: pid_t
    /// Global coordinates with a top-left origin. Only `x` is compared with
    /// AppKit frames, and `x` is the same in both spaces.
    let frame: CGRect
    let element: AXUIElement
}

/// Finds every app's menu bar items through Accessibility. This works whether
/// or not the window server lists each item as its own window, which makes it
/// the fallback on macOS versions where it doesn't (macOS 27).
enum MenuBarCatalog {
    private static let multiItemHosts: Set<String> = ["com.apple.controlcenter", "com.apple.systemuiserver"]

    /// The result of the last scan. Main thread only.
    private(set) static var latest: [MenuBarEntry] = []
    private static var lastScan = Date.distantPast
    private static var scanning = false

    /// Scans off the main thread and calls back on the main thread.
    static func load(completion: (([MenuBarEntry]) -> Void)? = nil) {
        let apps = NSWorkspace.shared.runningApplications
        DispatchQueue.global(qos: .userInitiated).async {
            let entries = scan(apps: apps)
            DispatchQueue.main.async {
                latest = entries
                lastScan = Date()
                completion?(entries)
            }
        }
    }

    /// Kicks off a background scan if the last one is older than `maxAge`.
    static func refreshIfStale(maxAge: TimeInterval = 2) {
        guard !scanning, Date().timeIntervalSince(lastScan) > maxAge, AXIsProcessTrusted() else { return }
        scanning = true
        load { _ in scanning = false }
    }

    /// Blocking. Safe to call from any thread.
    static func scan(apps: [NSRunningApplication]) -> [MenuBarEntry] {
        guard AXIsProcessTrusted() else { return [] }
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let candidates = apps.filter { $0.processIdentifier != ownPID }
        let lock = NSLock()
        var result: [MenuBarEntry] = []

        // Ask all apps at once; asking one after another adds up to seconds.
        DispatchQueue.concurrentPerform(iterations: candidates.count) { index in
            let found = entries(of: candidates[index])
            guard !found.isEmpty else { return }
            lock.lock()
            result.append(contentsOf: found)
            lock.unlock()
        }
        return result.sorted { $0.frame.minX < $1.frame.minX }
    }

    private static func entries(of app: NSRunningApplication) -> [MenuBarEntry] {
        let element = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(element, 0.1)
        guard let bar: AXUIElement = AX.attribute(element, "AXExtrasMenuBar"),
              let children: [AXUIElement] = AX.attribute(bar, kAXChildrenAttribute) else { return [] }

        let bundle = app.bundleIdentifier ?? "app.\(app.localizedName ?? "unknown")"
        let appName = app.localizedName ?? bundle
        let isSystemHost = multiItemHosts.contains(bundle)
        let hostsMany = isSystemHost || children.count > 1

        return children.compactMap { child in
            guard let frame = AX.frame(of: child) else { return nil }
            let label = [kAXDescriptionAttribute, kAXTitleAttribute, kAXHelpAttribute]
                .lazy.compactMap { (AX.attribute(child, $0) as String?) }.first { !$0.isEmpty }
            let identifier: String? = AX.attribute(child, kAXIdentifierAttribute)
            let name: String
            if let label, isSystemHost {
                name = label // "Wi‑Fi", "Battery", …
            } else if let label, hostsMany {
                name = "\(appName) – \(label)"
            } else {
                name = appName
            }
            return MenuBarEntry(
                key: hostsMany ? "\(bundle)#\(identifier ?? label ?? "item")" : bundle,
                name: name,
                appIcon: app.icon,
                pid: app.processIdentifier,
                frame: frame,
                element: child
            )
        }
    }

    /// The entry's current frame (items move when sections show and hide).
    static func currentFrame(of entry: MenuBarEntry) -> CGRect? { AX.frame(of: entry.element) }

    /// Opens the item's menu, as if it had been clicked.
    @discardableResult
    static func press(_ entry: MenuBarEntry) -> Bool {
        if AXUIElementPerformAction(entry.element, kAXPressAction as CFString) == .success { return true }
        // Some items ignore AXPress; click them instead, then put the pointer back.
        guard let frame = currentFrame(of: entry), frame.maxX > 0,
              NSScreen.screens.contains(where: { screenContainsCG(frame.center, $0) }) else { return false }
        let saved = CGEvent(source: nil)?.location
        let source = CGEventSource(stateID: .hidSystemState)
        for type in [CGEventType.leftMouseDown, .leftMouseUp] {
            CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: frame.center, mouseButton: .left)?
                .post(tap: .cghidEventTap)
        }
        if let saved { CGWarpMouseCursorPosition(saved) }
        return true
    }

    private static func screenContainsCG(_ point: CGPoint, _ screen: NSScreen) -> Bool {
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        let flipped = NSRect(x: screen.frame.minX, y: primaryHeight - screen.frame.maxY,
                             width: screen.frame.width, height: screen.frame.height)
        return flipped.contains(point)
    }

    // MARK: - Stand-in windows (macOS 27)

    private static var syntheticIDs: [String: CGWindowID] = [:]
    private static var nextSyntheticID: CGWindowID = 0x7000_0000

    /// The last scan as window-like records, for when the window server no
    /// longer lists items one by one. IDs stay the same for the same item.
    static func standInWindows() -> [MenuBarItemWindow] {
        refreshIfStale()
        return latest.map { entry in
            let id = syntheticIDs[entry.key] ?? {
                nextSyntheticID += 1
                syntheticIDs[entry.key] = nextSyntheticID
                return nextSyntheticID
            }()
            return MenuBarItemWindow(id: id, pid: entry.pid, frame: entry.frame)
        }
    }
}

private extension CGRect {
    var center: CGPoint { CGPoint(x: midX, y: midY) }
}

/// Small Accessibility helpers.
enum AX {
    static func attribute<T>(_ element: AXUIElement, _ name: String) -> T? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        if T.self == AXUIElement.self {
            guard let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
            return (value as! AXUIElement) as? T
        }
        return value as? T
    }

    static func frame(of element: AXUIElement) -> CGRect? {
        guard let position: AXValue = attribute(element, kAXPositionAttribute),
              let size: AXValue = attribute(element, kAXSizeAttribute) else { return nil }
        var point = CGPoint.zero
        var extent = CGSize.zero
        guard AXValueGetValue(position, .cgPoint, &point), AXValueGetValue(size, .cgSize, &extent) else { return nil }
        return CGRect(origin: point, size: extent)
    }

    /// Right edge of the frontmost app's menus (File, Edit, …), in global x.
    static func appMenusMaxX() -> CGFloat? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        let element = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(element, 0.1)
        guard let bar: AXUIElement = attribute(element, kAXMenuBarAttribute),
              let children: [AXUIElement] = attribute(bar, kAXChildrenAttribute) else { return nil }
        return children.compactMap { frame(of: $0)?.maxX }.max()
    }
}
