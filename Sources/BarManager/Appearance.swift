import AppKit

/// Tints the menu bar and draws an optional line under it, with one
/// click-through window per screen sitting just below the menu bar's items.
final class MenuBarTint {
    private var panels: [NSPanel] = []
    private var observers: [NSObjectProtocol] = []

    init() {
        // Screens settle a moment after a Space switch; measure after that.
        let reapply: (Notification) -> Void = { [weak self] _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { self?.apply() }
        }
        observers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main, using: reapply))
        // Full-screen apps hide the menu bar; the tint must go with it.
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main, using: reapply))
    }

    deinit {
        observers.forEach { NotificationCenter.default.removeObserver($0); NSWorkspace.shared.notificationCenter.removeObserver($0) }
    }

    static func color(fromHex hex: String?) -> NSColor? {
        guard var hex, hex.hasPrefix("#") else { return nil }
        hex.removeFirst()
        guard hex.count == 6, let value = UInt32(hex, radix: 16) else { return nil }
        return NSColor(srgbRed: CGFloat((value >> 16) & 0xFF) / 255, green: CGFloat((value >> 8) & 0xFF) / 255,
                       blue: CGFloat(value & 0xFF) / 255, alpha: 1)
    }

    static func hex(from color: NSColor) -> String {
        let rgb = color.usingColorSpace(.sRGB) ?? color
        return String(format: "#%02X%02X%02X", Int(round(rgb.redComponent * 255)),
                      Int(round(rgb.greenComponent * 255)), Int(round(rgb.blueComponent * 255)))
    }

    /// Stronger than this and the icons under the tint get hard to read.
    static let maxOpacity = 0.6

    func apply() {
        panels.forEach { $0.orderOut(nil) }
        panels = []
        let tint = Self.color(fromHex: Settings.tintColor)
        guard tint != nil || Settings.showBorder else { return }

        for screen in NSScreen.screens {
            let barHeight = screen.frame.maxY - screen.visibleFrame.maxY
            // No menu bar on this screen right now (a full-screen app, or it auto-hides).
            guard barHeight > 10 else { continue }
            let height = barHeight
            let frame = NSRect(x: screen.frame.minX, y: screen.frame.maxY - height, width: screen.frame.width, height: height)

            let panel = TintPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = false
            panel.ignoresMouseEvents = true
            // On the icons' own level. macOS 26 draws the menu bar opaque above any
            // lower level, and there's no gap between its background and the icons,
            // so the tint colors the whole bar, icons and app menus included.
            // Menus open above it; clicks pass through.
            panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.statusWindow)))
            panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenNone]
            panel.sharingType = .none

            let view = TintView(frame: NSRect(origin: .zero, size: frame.size))
            view.tint = tint?.withAlphaComponent(min(Settings.tintOpacity, Self.maxOpacity))
            view.showBorder = Settings.showBorder
            panel.contentView = view
            panel.orderFrontRegardless()
            panel.setFrame(frame, display: true) // again, in case macOS nudged it while ordering in
            panels.append(panel)
        }
    }

    func remove() {
        panels.forEach { $0.orderOut(nil) }
        panels = []
    }
}

/// macOS moves ordinary windows out from under the menu bar; the tint has to sit on it.
private final class TintPanel: NSPanel {
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

private final class TintView: NSView {
    var tint: NSColor?
    var showBorder = false

    override func draw(_ dirtyRect: NSRect) {
        if let tint {
            tint.setFill()
            bounds.fill()
        }
        if showBorder {
            NSColor.separatorColor.withAlphaComponent(0.8).setFill()
            NSRect(x: 0, y: 0, width: bounds.width, height: 1).fill()
        }
    }
}

/// The macOS-wide space between menu bar icons. Apps pick it up as they
/// start, so it fully applies after logging out and back in.
enum MenuBarSpacing {
    private static let keys = ["NSStatusItemSpacing", "NSStatusItemSelectionPadding"]

    static func apply(_ spacing: ItemSpacing) {
        for key in keys {
            let value = spacing.points.map { $0 as CFNumber }
            CFPreferencesSetValue(key as CFString, value, kCFPreferencesAnyApplication, kCFPreferencesCurrentUser, kCFPreferencesCurrentHost)
        }
        CFPreferencesSynchronize(kCFPreferencesAnyApplication, kCFPreferencesCurrentUser, kCFPreferencesCurrentHost)
    }
}
