import AppKit

/// Which app a menu bar item belongs to. On macOS 26 every item window is
/// owned by Control Center, so we match windows to apps through Accessibility:
/// each app's "extras menu bar" lists its status items with their frames.
struct ItemIdentity {
    /// Stable across launches: the bundle ID, plus the item's label for apps
    /// (like Control Center) that own several items.
    let key: String
    let name: String
    let appIcon: NSImage?

    /// Window ID → identity. Main thread only.
    private static var cache: [CGWindowID: ItemIdentity] = [:]

    static func cached(_ id: CGWindowID) -> ItemIdentity? { cache[id] }

    static func forgetCache() { cache = [:] }

    /// Looks up identities off the main thread and calls back on the main thread.
    static func resolve(_ windows: [MenuBarItemWindow], completion: (([CGWindowID: ItemIdentity]) -> Void)? = nil) {
        let missing = windows.filter { cache[$0.id] == nil }
        guard !missing.isEmpty else {
            completion?(cache.filter { id, _ in windows.contains { $0.id == id } })
            return
        }
        let apps = NSWorkspace.shared.runningApplications
        DispatchQueue.global(qos: .userInitiated).async {
            let found = lookUp(missing, apps: apps)
            DispatchQueue.main.async {
                cache.merge(found) { $1 }
                completion?(cache.filter { id, _ in windows.contains { $0.id == id } })
            }
        }
    }

    private static func lookUp(_ windows: [MenuBarItemWindow], apps: [NSRunningApplication]) -> [CGWindowID: ItemIdentity] {
        guard AXIsProcessTrusted(), !windows.isEmpty else { return [:] }
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let multiItemHosts: Set<String> = ["com.apple.controlcenter", "com.apple.systemuiserver"]
        let lock = NSLock()
        var result: [CGWindowID: ItemIdentity] = [:]
        let candidates = apps.filter { $0.processIdentifier != ownPID }

        // Ask all apps at once; asking one after another adds up to seconds.
        DispatchQueue.concurrentPerform(iterations: candidates.count) { index in
            let app = candidates[index]
            let element = AXUIElementCreateApplication(app.processIdentifier)
            AXUIElementSetMessagingTimeout(element, 0.1)
            guard let bar: AXUIElement = attribute(element, "AXExtrasMenuBar"),
                  let children: [AXUIElement] = attribute(bar, kAXChildrenAttribute) else { return }

            for child in children {
                guard let frame = frame(of: child),
                      let window = windows.first(where: { abs($0.frame.minX - frame.minX) < 2 && abs($0.frame.width - frame.width) < 3 })
                else { continue }
                let bundle = app.bundleIdentifier ?? "app.\(app.localizedName ?? "unknown")"
                let appName = app.localizedName ?? bundle
                let label = [kAXDescriptionAttribute, kAXTitleAttribute, kAXHelpAttribute]
                    .lazy.compactMap { (attribute(child, $0) as String?) }.first { !$0.isEmpty }
                let identifier: String? = attribute(child, kAXIdentifierAttribute)
                let isSystemHost = multiItemHosts.contains(bundle)
                let hostsMany = isSystemHost || children.count > 1
                let name: String
                if let label, isSystemHost {
                    name = label // "Wi‑Fi", "Battery", …
                } else if let label, hostsMany {
                    name = "\(appName) – \(label)"
                } else {
                    name = appName
                }
                let identity = ItemIdentity(
                    key: hostsMany ? "\(bundle)#\(identifier ?? label ?? "item")" : bundle,
                    name: name,
                    appIcon: app.icon
                )
                lock.lock()
                result[window.id] = identity
                lock.unlock()
            }
        }
        return result
    }

    private static func attribute<T>(_ element: AXUIElement, _ name: String) -> T? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        if T.self == AXUIElement.self {
            guard let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
            return (value as! AXUIElement) as? T
        }
        return value as? T
    }

    private static func frame(of element: AXUIElement) -> CGRect? {
        guard let position: AXValue = attribute(element, kAXPositionAttribute),
              let size: AXValue = attribute(element, kAXSizeAttribute) else { return nil }
        var point = CGPoint.zero
        var extent = CGSize.zero
        guard AXValueGetValue(position, .cgPoint, &point), AXValueGetValue(size, .cgSize, &extent) else { return nil }
        return CGRect(origin: point, size: extent)
    }
}
