import AppKit

/// Moves other apps' menu bar items by posting a synthetic ⌘-drag aimed
/// straight at the item's window, so it works even while the item is off
/// screen. Needs Accessibility permission. Call from `ItemMover.queue`.
enum ItemMover {
    enum Destination {
        case leftOf(MenuBarItemWindow)
        case rightOf(MenuBarItemWindow)
    }

    static let queue = DispatchQueue(label: "BarManager.ItemMover")

    static var hasPermission: Bool { CGPreflightPostEventAccess() }

    @discardableResult
    static func requestPermission() -> Bool { CGRequestPostEventAccess() }

    /// Runs a batch of moves with the cursor hidden, then puts it back where it was.
    static func batch(_ work: () -> Void) {
        let cursor = CGEvent(source: nil)?.location
        CGDisplayHideCursor(CGMainDisplayID())
        work()
        if let cursor { CGWarpMouseCursorPosition(cursor) }
        CGDisplayShowCursor(CGMainDisplayID())
    }

    /// Returns true once the item's frame has changed.
    @discardableResult
    static func move(_ item: MenuBarItemWindow, to destination: Destination) -> Bool {
        guard hasPermission else { return false }
        let endPoint: CGPoint
        switch destination {
        case .leftOf(let target):
            guard target.id != item.id else { return true }
            endPoint = CGPoint(x: target.frame.minX, y: target.frame.midY)
        case .rightOf(let target):
            guard target.id != item.id else { return true }
            endPoint = CGPoint(x: target.frame.maxX, y: target.frame.midY)
        }

        guard let source = CGEventSource(stateID: .combinedSessionState) else { return false }
        source.setLocalEventsFilterDuringSuppressionState(
            [.permitLocalMouseEvents, .permitLocalKeyboardEvents, .permitSystemDefinedEvents],
            state: .eventSuppressionStateSuppressionInterval
        )
        source.localEventsSuppressionInterval = 0

        // The press starts far off screen so the real cursor can't interfere;
        // the window fields route every event to the item being dragged.
        let startPoint = CGPoint(x: 20_000, y: 20_000)
        let originalX = item.frame.minX
        for _ in 0..<2 {
            post(.leftMouseDown, at: startPoint, to: item, source: source)
            usleep(15_000)
            post(.leftMouseDragged, at: endPoint, to: item, source: source)
            usleep(15_000)
            post(.leftMouseUp, at: endPoint, to: item, source: source)

            for _ in 0..<20 {
                usleep(20_000)
                if let now = MenuBarItemWindow.all().first(where: { $0.id == item.id }),
                   abs(now.frame.minX - originalX) > 0.5 {
                    return true
                }
            }
        }
        NSLog("BarManager: couldn't move menu bar item %u", item.id)
        return false
    }

    /// Undocumented field that names the event's target window.
    private static let windowField = CGEventField(rawValue: 0x33)

    private static func post(_ type: CGEventType, at point: CGPoint, to window: MenuBarItemWindow, source: CGEventSource) {
        guard let event = CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: point, mouseButton: .left) else { return }
        event.flags = .maskCommand
        event.setIntegerValueField(.eventTargetUnixProcessID, value: Int64(window.pid))
        event.setIntegerValueField(.mouseEventWindowUnderMousePointer, value: Int64(window.id))
        event.setIntegerValueField(.mouseEventWindowUnderMousePointerThatCanHandleThisEvent, value: Int64(window.id))
        if let windowField { event.setIntegerValueField(windowField, value: Int64(window.id)) }
        event.post(tap: .cgSessionEventTap)
    }
}
