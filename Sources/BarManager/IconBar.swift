import AppKit

/// A menu bar item with the picture to show for it.
struct PicturedEntry {
    let entry: MenuBarEntry
    /// A snapshot of the icon itself if there is one, else the app's icon.
    let image: NSImage?
    let section: MenuBarSection
    /// False when macOS has no room to draw the icon at all (a crowded menu bar
    /// next to the notch): it has no window, so it can't be shown or opened.
    var hasRoom = true
}

enum MenuBarSection: String {
    case visible, hidden, alwaysHidden

    var title: String {
        switch self {
        case .visible: "Visible"
        case .hidden: "Hidden"
        case .alwaysHidden: "Always Hidden"
        }
    }
}

/// Hidden icons in a strip below the menu bar, for when they don't fit next
/// to the notch or the app's menus. Clicking one opens it.
final class IconBar: NSObject {
    var onChoose: ((MenuBarEntry) -> Void)?
    var onClose: (() -> Void)?

    private var panel: NSPanel?
    private var clickMonitor: Any?

    var isOpen: Bool { panel != nil }

    /// Shows the bar under `anchor` (the arrow's frame in AppKit coordinates).
    func show(_ items: [PicturedEntry], below anchor: NSRect) {
        close(notify: false)
        let screen = NSScreen.screens.first { $0.frame.contains(NSPoint(x: anchor.midX, y: anchor.midY)) } ?? NSScreen.main
        guard let screen else { return }

        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.spacing = 2
        stack.edgeInsets = NSEdgeInsets(top: 4, left: 6, bottom: 4, right: 6)

        if items.isEmpty {
            let label = NSTextField(labelWithString: "No hidden icons")
            label.textColor = .secondaryLabelColor
            label.font = .menuFont(ofSize: 0)
            stack.addArrangedSubview(label)
        }
        for (index, item) in items.enumerated() {
            let button = NSButton(title: "", target: self, action: #selector(choose(_:)))
            button.tag = index
            button.bezelStyle = .accessoryBarAction
            button.isBordered = false
            button.showsBorderOnlyWhileMouseInside = true
            button.imagePosition = .imageOnly
            button.image = Self.fit(item.image, height: 18)
            button.toolTip = item.entry.name
            button.setAccessibilityLabel(item.entry.name)
            button.widthAnchor.constraint(greaterThanOrEqualToConstant: 26).isActive = true
            button.heightAnchor.constraint(equalToConstant: 24).isActive = true
            stack.addArrangedSubview(button)
        }
        self.items = items.map(\.entry)

        let background = NSVisualEffectView()
        background.material = .menu
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = 9
        background.layer?.masksToBounds = true
        background.addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: background.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: background.trailingAnchor),
            stack.topAnchor.constraint(equalTo: background.topAnchor),
            stack.bottomAnchor.constraint(equalTo: background.bottomAnchor),
        ])
        let size = stack.fittingSize
        let maxWidth = screen.visibleFrame.width - 16
        let width = min(size.width, maxWidth)
        // Right edge under the arrow's right edge, kept on screen.
        var x = anchor.maxX - width
        x = min(max(x, screen.visibleFrame.minX + 8), screen.visibleFrame.maxX - width - 8)
        let y = screen.visibleFrame.maxY - size.height - 4
        let frame = NSRect(x: x, y: y, width: width, height: size.height)

        let panel = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle]
        panel.contentView = background
        panel.setAccessibilityLabel("Hidden icons")
        panel.orderFrontRegardless()
        self.panel = panel

        // Clicking anywhere else closes it.
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.close()
        }
    }

    private var items: [MenuBarEntry] = []

    @objc private func choose(_ sender: NSButton) {
        guard items.indices.contains(sender.tag) else { return }
        let entry = items[sender.tag]
        close(notify: false)
        onChoose?(entry)
    }

    func close(notify: Bool = true) {
        if let clickMonitor { NSEvent.removeMonitor(clickMonitor) }
        clickMonitor = nil
        guard let panel else { return }
        panel.orderOut(nil)
        self.panel = nil
        if notify { onClose?() }
    }

    private static func fit(_ image: NSImage?, height: CGFloat) -> NSImage? {
        guard let image else { return NSImage(systemSymbolName: "questionmark.square.dashed", accessibilityDescription: nil) }
        let width = min(image.size.width * height / max(image.size.height, 1), 60)
        return NSImage(size: NSSize(width: width, height: height), flipped: false) { rect in
            image.draw(in: rect)
            return true
        }
    }
}
