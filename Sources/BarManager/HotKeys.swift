import AppKit
import Carbon.HIToolbox

/// A key plus modifiers, stored the way Carbon's hotkey API wants them.
struct KeyCombo: Codable, Equatable, Hashable {
    let keyCode: UInt32
    /// Carbon modifier flags (cmdKey, optionKey, controlKey, shiftKey).
    let modifiers: UInt32

    init(keyCode: UInt32, modifiers: UInt32) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    /// From a key-down event; nil for combos that would steal ordinary typing.
    init?(event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        var carbon: UInt32 = 0
        if flags.contains(.command) { carbon |= UInt32(cmdKey) }
        if flags.contains(.option) { carbon |= UInt32(optionKey) }
        if flags.contains(.control) { carbon |= UInt32(controlKey) }
        if flags.contains(.shift) { carbon |= UInt32(shiftKey) }
        let code = UInt32(event.keyCode)
        let needsModifier = !Self.functionKeys.contains(code)
        // Shift alone isn't enough: ⇧A is just a capital A.
        guard !needsModifier || carbon & ~UInt32(shiftKey) != 0 else { return nil }
        self.init(keyCode: code, modifiers: carbon)
    }

    var displayString: String {
        var text = ""
        if modifiers & UInt32(controlKey) != 0 { text += "⌃" }
        if modifiers & UInt32(optionKey) != 0 { text += "⌥" }
        if modifiers & UInt32(shiftKey) != 0 { text += "⇧" }
        if modifiers & UInt32(cmdKey) != 0 { text += "⌘" }
        return text + (Self.keyNames[keyCode] ?? "Key \(keyCode)")
    }

    private static let functionKeys: Set<UInt32> = [
        UInt32(kVK_F1), UInt32(kVK_F2), UInt32(kVK_F3), UInt32(kVK_F4), UInt32(kVK_F5), UInt32(kVK_F6),
        UInt32(kVK_F7), UInt32(kVK_F8), UInt32(kVK_F9), UInt32(kVK_F10), UInt32(kVK_F11), UInt32(kVK_F12),
        UInt32(kVK_F13), UInt32(kVK_F14), UInt32(kVK_F15), UInt32(kVK_F16), UInt32(kVK_F17), UInt32(kVK_F18),
        UInt32(kVK_F19), UInt32(kVK_F20),
    ]

    /// Names for the US layout; good enough to recognize a shortcut.
    static let keyNames: [UInt32: String] = {
        var names: [Int: String] = [
            kVK_ANSI_A: "A", kVK_ANSI_B: "B", kVK_ANSI_C: "C", kVK_ANSI_D: "D", kVK_ANSI_E: "E", kVK_ANSI_F: "F",
            kVK_ANSI_G: "G", kVK_ANSI_H: "H", kVK_ANSI_I: "I", kVK_ANSI_J: "J", kVK_ANSI_K: "K", kVK_ANSI_L: "L",
            kVK_ANSI_M: "M", kVK_ANSI_N: "N", kVK_ANSI_O: "O", kVK_ANSI_P: "P", kVK_ANSI_Q: "Q", kVK_ANSI_R: "R",
            kVK_ANSI_S: "S", kVK_ANSI_T: "T", kVK_ANSI_U: "U", kVK_ANSI_V: "V", kVK_ANSI_W: "W", kVK_ANSI_X: "X",
            kVK_ANSI_Y: "Y", kVK_ANSI_Z: "Z",
            kVK_ANSI_0: "0", kVK_ANSI_1: "1", kVK_ANSI_2: "2", kVK_ANSI_3: "3", kVK_ANSI_4: "4",
            kVK_ANSI_5: "5", kVK_ANSI_6: "6", kVK_ANSI_7: "7", kVK_ANSI_8: "8", kVK_ANSI_9: "9",
            kVK_ANSI_Minus: "-", kVK_ANSI_Equal: "=", kVK_ANSI_LeftBracket: "[", kVK_ANSI_RightBracket: "]",
            kVK_ANSI_Semicolon: ";", kVK_ANSI_Quote: "'", kVK_ANSI_Comma: ",", kVK_ANSI_Period: ".",
            kVK_ANSI_Slash: "/", kVK_ANSI_Backslash: "\\", kVK_ANSI_Grave: "`",
            kVK_Space: "Space", kVK_Return: "↩", kVK_Tab: "⇥", kVK_Delete: "⌫", kVK_ForwardDelete: "⌦",
            kVK_Escape: "⎋", kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓",
            kVK_Home: "↖", kVK_End: "↘", kVK_PageUp: "⇞", kVK_PageDown: "⇟",
        ]
        for (index, key) in [kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6, kVK_F7, kVK_F8, kVK_F9, kVK_F10,
                             kVK_F11, kVK_F12, kVK_F13, kVK_F14, kVK_F15, kVK_F16, kVK_F17, kVK_F18, kVK_F19, kVK_F20].enumerated() {
            names[key] = "F\(index + 1)"
        }
        return Dictionary(uniqueKeysWithValues: names.map { (UInt32($0.key), $0.value) })
    }()
}

/// What a global shortcut does. Stored as a string so it can key a dictionary.
enum HotKeyAction: Hashable {
    case toggleHidden
    case showAll
    case search
    /// Opens the menu of one menu bar item (by `MenuBarEntry.key`).
    case openItem(String)
    case applyProfile(UUID)

    var id: String {
        switch self {
        case .toggleHidden: "toggle"
        case .showAll: "showAll"
        case .search: "search"
        case .openItem(let key): "item:\(key)"
        case .applyProfile(let id): "profile:\(id.uuidString)"
        }
    }

    init?(id: String) {
        switch id {
        case "toggle": self = .toggleHidden
        case "showAll": self = .showAll
        case "search": self = .search
        default:
            if id.hasPrefix("item:") {
                self = .openItem(String(id.dropFirst(5)))
            } else if id.hasPrefix("profile:"), let uuid = UUID(uuidString: String(id.dropFirst(8))) {
                self = .applyProfile(uuid)
            } else {
                return nil
            }
        }
    }
}

/// Registers system-wide shortcuts with Carbon, which needs no permission.
final class HotKeyCenter {
    static let shared = HotKeyCenter()

    var onAction: ((HotKeyAction) -> Void)?

    private var refs: [EventHotKeyRef] = []
    private var actions: [UInt32: HotKeyAction] = [:]
    private var handlerInstalled = false
    /// While recording a new shortcut, existing ones mustn't fire.
    var isPaused = false {
        didSet { if isPaused != oldValue { isPaused ? unregisterAll() : reload() } }
    }

    /// Re-registers everything in `Settings.hotKeys`.
    func reload() {
        unregisterAll()
        guard !isPaused else { return }
        installHandler()
        var next: UInt32 = 1
        for (id, combo) in Settings.hotKeys {
            guard let action = HotKeyAction(id: id) else { continue }
            var ref: EventHotKeyRef?
            let hotKeyID = EventHotKeyID(signature: OSType(0x424D_6772), id: next) // "BMgr"
            let status = RegisterEventHotKey(combo.keyCode, combo.modifiers, hotKeyID, GetApplicationEventTarget(), 0, &ref)
            if status == noErr, let ref {
                refs.append(ref)
                actions[next] = action
                next += 1
            } else {
                NSLog("BarManager: couldn't register shortcut \(combo.displayString) (\(status))")
            }
        }
    }

    private func unregisterAll() {
        refs.forEach { UnregisterEventHotKey($0) }
        refs = []
        actions = [:]
    }

    fileprivate func fire(_ id: UInt32) {
        guard let action = actions[id] else { return }
        onAction?(action)
    }

    private func installHandler() {
        guard !handlerInstalled else { return }
        handlerInstalled = true
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var hotKeyID = EventHotKeyID()
            let status = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                           nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
            guard status == noErr else { return status }
            let id = hotKeyID.id
            DispatchQueue.main.async { HotKeyCenter.shared.fire(id) }
            return noErr
        }, 1, &spec, nil, nil)
    }
}
