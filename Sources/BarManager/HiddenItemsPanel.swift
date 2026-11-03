import AppKit
import ScreenCaptureKit

/// A menu bar item window as seen by the window server. On macOS 26 every
/// status item is hosted by Control Center, so the frame is all we can rely on.
struct MenuBarItemWindow: Equatable {
    let id: CGWindowID
    /// Global coordinates with a top-left origin (CGWindowList space). Only `x`
    /// is compared with AppKit frames, and `x` is the same in both spaces.
    let frame: CGRect

    static func all() -> [MenuBarItemWindow] {
        let statusLevel = Int(CGWindowLevelForKey(.statusWindow))
        guard let list = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] else { return [] }
        return list.compactMap { info in
            guard (info[kCGWindowLayer as String] as? Int) == statusLevel,
                  let number = info[kCGWindowNumber as String] as? CGWindowID,
                  let bounds = info[kCGWindowBounds as String] as? NSDictionary,
                  let frame = CGRect(dictionaryRepresentation: bounds) else { return nil }
            // Real items sit at the very top and are small. This drops popups that
            // share the level and our own stretched dividers.
            guard frame.minY < 1, frame.height <= 50, frame.width > 2, frame.width < 600 else { return nil }
            return MenuBarItemWindow(id: number, frame: frame)
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

/// Captures images of menu bar item windows. Needs Screen Recording permission.
enum ItemCapture {
    static func capture(_ ids: [CGWindowID]) async -> [CGWindowID: NSImage] {
        guard CGPreflightScreenCaptureAccess(), !ids.isEmpty,
              let content = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        else { return [:] }

        let wanted = Set(ids)
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        var result: [CGWindowID: NSImage] = [:]
        for window in content.windows where wanted.contains(window.windowID) {
            let config = SCStreamConfiguration()
            config.width = Int(window.frame.width * scale)
            config.height = Int(window.frame.height * scale)
            config.showsCursor = false
            config.ignoreShadowsSingleWindow = true
            let filter = SCContentFilter(desktopIndependentWindow: window)
            if let cgImage = try? await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config) {
                result[window.windowID] = NSImage(cgImage: cgImage, size: window.frame.size)
            }
        }
        return result
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

private final class ItemButton: NSButton {
    var item: MenuBarItemWindow?
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// Floating strip under the menu bar that lists every hidden item, wrapping
/// into rows so even a long list fits.
final class HiddenItemsPanel: NSPanel {
    var onSelect: ((MenuBarItemWindow) -> Void)?
    var onRequestPermission: (() -> Void)?

    private static let padding: CGFloat = 6
    private static let spacing: CGFloat = 2
    private static let rowHeight: CGFloat = 28
    private static let iconHeight: CGFloat = 22
    private static let maxWidth: CGFloat = 520

    private var items: [MenuBarItemWindow] = []
    private var images: [CGWindowID: NSImage] = [:]
    private var anchor: NSRect = .zero

    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        isFloatingPanel = true
        level = .popUpMenu
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = true
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
    }

    func show(items: [MenuBarItemWindow], images: [CGWindowID: NSImage], below anchor: NSRect) {
        self.items = items
        self.images = images
        self.anchor = anchor
        rebuild()
        orderFrontRegardless()
    }

    func update(images: [CGWindowID: NSImage]) {
        self.images = images
        if isVisible { rebuild() }
    }

    private func rebuild() {
        let needsPermission = !CGPreflightScreenCaptureAccess()
        var buttons: [NSView] = []

        for item in items {
            let button = ItemButton()
            button.item = item
            button.bezelStyle = .recessed
            button.showsBorderOnlyWhileMouseInside = true
            button.imagePosition = .imageOnly
            button.target = self
            button.action = #selector(itemClicked(_:))

            let width: CGFloat
            if let image = images[item.id] {
                let scale = Self.iconHeight / max(image.size.height, 1)
                let size = NSSize(width: image.size.width * scale, height: Self.iconHeight)
                let resized = NSImage(size: size, flipped: false) { rect in
                    image.draw(in: rect)
                    return true
                }
                button.image = resized
                width = max(size.width + 6, Self.rowHeight)
            } else {
                button.image = NSImage(systemSymbolName: "app.dashed", accessibilityDescription: "Hidden item")
                width = Self.rowHeight
            }
            button.frame = NSRect(x: 0, y: 0, width: width, height: Self.rowHeight)
            buttons.append(button)
        }

        if items.isEmpty {
            let label = NSTextField(labelWithString: "No hidden icons. ⌘-drag icons left of the divider to hide them.")
            label.font = .systemFont(ofSize: 12)
            label.textColor = .secondaryLabelColor
            label.sizeToFit()
            label.frame.size.height = Self.rowHeight
            buttons.append(label)
        }

        // Flow layout, right-aligned rows so the strip reads like the menu bar.
        var rows: [[NSView]] = [[]]
        var rowWidth: CGFloat = 0
        for view in buttons {
            let w = view.frame.width
            if rowWidth > 0, rowWidth + Self.spacing + w > Self.maxWidth {
                rows.append([])
                rowWidth = 0
            }
            rowWidth += (rowWidth > 0 ? Self.spacing : 0) + w
            rows[rows.count - 1].append(view)
        }
        let rowWidths = rows.map { row in row.reduce(0) { $0 + $1.frame.width } + Self.spacing * CGFloat(max(row.count - 1, 0)) }

        var permissionButton: NSButton?
        if needsPermission {
            let b = NSButton(title: "Allow Screen Recording to see the real icons…", target: self, action: #selector(permissionClicked))
            b.bezelStyle = .inline
            b.controlSize = .small
            b.font = .systemFont(ofSize: 11)
            b.sizeToFit()
            permissionButton = b
        }

        let contentWidth = max(rowWidths.max() ?? 0, permissionButton?.frame.width ?? 0)
        let width = contentWidth + Self.padding * 2
        let permissionHeight: CGFloat = permissionButton == nil ? 0 : 24
        let height = CGFloat(rows.count) * Self.rowHeight + CGFloat(rows.count - 1) * Self.spacing
            + Self.padding * 2 + permissionHeight

        let effect = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: width, height: height))
        effect.material = .menu
        effect.state = .active
        effect.blendingMode = .behindWindow
        effect.maskImage = Self.roundedMask(radius: 10)

        var y = height - Self.padding - Self.rowHeight
        for (index, row) in rows.enumerated() {
            var x = width - Self.padding - rowWidths[index]
            for view in row {
                view.frame.origin = NSPoint(x: x, y: y)
                effect.addSubview(view)
                x += view.frame.width + Self.spacing
            }
            y -= Self.rowHeight + Self.spacing
        }
        if let permissionButton {
            permissionButton.frame.origin = NSPoint(x: (width - permissionButton.frame.width) / 2, y: Self.padding)
            effect.addSubview(permissionButton)
        }

        contentView = effect

        let screen = NSScreen.screens.first { $0.frame.contains(NSPoint(x: anchor.midX, y: anchor.midY)) } ?? NSScreen.main
        let bounds = screen?.frame ?? .zero
        var originX = min(anchor.maxX, bounds.maxX - 4) - width
        originX = max(originX, bounds.minX + 4)
        setFrame(NSRect(x: originX, y: anchor.minY - 4 - height, width: width, height: height), display: true)
    }

    @objc private func itemClicked(_ sender: ItemButton) {
        guard let item = sender.item else { return }
        onSelect?(item)
    }

    @objc private func permissionClicked() { onRequestPermission?() }

    private static func roundedMask(radius: CGFloat) -> NSImage {
        let edge = radius * 2 + 1
        let image = NSImage(size: NSSize(width: edge, height: edge), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        image.resizingMode = .stretch
        return image
    }
}
