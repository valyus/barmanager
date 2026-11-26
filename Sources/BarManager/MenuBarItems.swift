import AppKit

/// A menu bar item window as seen by the window server. On macOS 26 every
/// status item is hosted by Control Center, so the frame is all we can rely on.
struct MenuBarItemWindow: Equatable {
    let id: CGWindowID
    let pid: pid_t
    /// Global coordinates with a top-left origin (CGWindowList space). Only `x`
    /// is compared with AppKit frames, and `x` is the same in both spaces.
    let frame: CGRect

    /// True when the window server doesn't list items one by one (macOS 27),
    /// so positions come from Accessibility instead.
    private(set) static var usingStandIns = false

    /// Every other app's menu bar item, left to right. Main thread only.
    static func all() -> [MenuBarItemWindow] {
        let windows = windowServerItems()
        // One window (or none) for the whole menu bar means the window server
        // has stopped listing items separately; ask Accessibility instead.
        if windows.count <= 1, AXIsProcessTrusted() {
            let standIns = MenuBarCatalog.standInWindows()
            if standIns.count > windows.count {
                if !usingStandIns { NSLog("BarManager: menu bar items aren't separate windows; using Accessibility positions") }
                usingStandIns = true
                return standIns
            }
        }
        usingStandIns = false
        return windows
    }

    private static func windowServerItems() -> [MenuBarItemWindow] {
        let statusLevel = Int(CGWindowLevelForKey(.statusWindow))
        let ownPID = ProcessInfo.processInfo.processIdentifier
        guard let list = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] else { return [] }
        return list.compactMap { info in
            guard (info[kCGWindowLayer as String] as? Int) == statusLevel,
                  (info[kCGWindowOwnerPID as String] as? pid_t) != ownPID,
                  let number = info[kCGWindowNumber as String] as? CGWindowID,
                  let pid = info[kCGWindowOwnerPID as String] as? pid_t,
                  let bounds = info[kCGWindowBounds as String] as? NSDictionary,
                  let frame = CGRect(dictionaryRepresentation: bounds) else { return nil }
            // Real items sit at the very top and are small. This drops popups that
            // share the level and our own stretched items.
            guard frame.minY < 1, frame.height <= 50, frame.width > 2, frame.width < 600 else { return nil }
            return MenuBarItemWindow(id: number, pid: pid, frame: frame)
        }
        .sorted { $0.frame.minX < $1.frame.minX }
    }

    /// True while a menu (or a popover-style window the pointer is in) is open,
    /// so we don't yank an item away while someone is using it.
    static func somethingIsOpen() -> Bool {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return false }
        let menuLevel = Int(CGWindowLevelForKey(.popUpMenuWindow))
        let statusLevel = Int(CGWindowLevelForKey(.statusWindow))
        let mouse = NSEvent.mouseLocation
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        let mouseCG = CGPoint(x: mouse.x, y: primaryHeight - mouse.y)
        let ownPID = ProcessInfo.processInfo.processIdentifier

        for info in list {
            guard let layer = info[kCGWindowLayer as String] as? Int,
                  let bounds = info[kCGWindowBounds as String] as? NSDictionary,
                  let frame = CGRect(dictionaryRepresentation: bounds) else { continue }
            if (info[kCGWindowOwnerPID as String] as? pid_t) == ownPID { continue }
            if layer == menuLevel { return true }
            let isMenuBarItem = layer == statusLevel && frame.minY < 1 && frame.height <= 50
            if layer >= 3, !isMenuBarItem, frame.contains(mouseCG) { return true }
        }
        return false
    }
}

extension CGRect {
    /// True when an Accessibility frame and a window frame are the same menu bar
    /// item. Some items' windows are wider than their Accessibility frame
    /// (padding on both sides), so compare centers, not edges.
    func isSameMenuBarItem(as other: CGRect) -> Bool {
        abs(midX - other.midX) <= 3 && abs(width - other.width) <= 20
    }
}

/// Forwards mouse enter/exit from a tracking area to closures.
final class HoverTracker: NSResponder {
    var onEnter: (() -> Void)?
    var onExit: (() -> Void)?

    override init() { super.init() }
    required init?(coder: NSCoder) { fatalError() }

    override func mouseEntered(with event: NSEvent) { onEnter?() }
    override func mouseExited(with event: NSEvent) { onExit?() }
}
