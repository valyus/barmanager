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
            let found = match(missing, to: MenuBarCatalog.scan(apps: apps))
            DispatchQueue.main.async {
                cache.merge(found) { $1 }
                completion?(cache.filter { id, _ in windows.contains { $0.id == id } })
            }
        }
    }

    static func match(_ windows: [MenuBarItemWindow], to entries: [MenuBarEntry]) -> [CGWindowID: ItemIdentity] {
        var result: [CGWindowID: ItemIdentity] = [:]
        for entry in entries {
            guard let window = windows.first(where: {
                abs($0.frame.minX - entry.frame.minX) < 2 && abs($0.frame.width - entry.frame.width) < 3
            }) else { continue }
            result[window.id] = ItemIdentity(key: entry.key, name: entry.name, appIcon: entry.appIcon)
        }
        return result
    }
}
