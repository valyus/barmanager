import Foundation

enum Settings {
    private static let defaults = UserDefaults.standard

    private enum Key {
        static let autoHideDelay = "autoHideDelay"
        static let isCollapsed = "isCollapsed"
        static let alwaysHiddenEnabled = "alwaysHiddenEnabled"
        static let hasShownWelcome = "hasShownWelcome"
        // New key so earlier installs (where hover was the default) switch to click.
        static let showOnHover = "expandOnHover"
        static let playSounds = "playSounds"
        static let soundTheme = "soundTheme"
        static let arrowStyle = "arrowStyle"
        static let soundVolume = "soundVolume"
        static let showChangedIcons = "showChangedIcons"
        static let neverShowWhenChanged = "neverShowWhenChanged"
        static let hotKeys = "hotKeys"
        static let revealMode = "revealMode"
        static let triggers = "triggers"
        static let profiles = "profiles"
        static let activeProfile = "activeProfile"
        static let tintColor = "tintColor"
        static let tintOpacity = "tintOpacity"
        static let showBorder = "showBorder"
        static let spacerCount = "spacerCount"
        static let itemSpacing = "itemSpacing"
    }

    /// Every key BarManager owns, for export, import and reset.
    static let allKeys: [String] = [
        Key.autoHideDelay, Key.isCollapsed, Key.alwaysHiddenEnabled, Key.showOnHover, Key.playSounds,
        Key.soundTheme, Key.arrowStyle, Key.soundVolume, Key.showChangedIcons, Key.neverShowWhenChanged,
        Key.hotKeys, Key.revealMode, Key.triggers, Key.profiles, Key.activeProfile, Key.tintColor,
        Key.tintOpacity, Key.showBorder, Key.spacerCount, Key.itemSpacing,
    ]

    /// Where macOS keeps the positions of BarManager's own items.
    static let positionKeyPrefix = "NSStatusItem Preferred Position BarManager."

    /// Seconds before the hidden section collapses again. 0 = never.
    static var autoHideDelay: TimeInterval {
        get { defaults.object(forKey: Key.autoHideDelay) as? TimeInterval ?? 10 }
        set { defaults.set(newValue, forKey: Key.autoHideDelay) }
    }

    static var isCollapsed: Bool {
        get { defaults.object(forKey: Key.isCollapsed) as? Bool ?? false }
        set { defaults.set(newValue, forKey: Key.isCollapsed) }
    }

    static var alwaysHiddenEnabled: Bool {
        get { defaults.bool(forKey: Key.alwaysHiddenEnabled) }
        set { defaults.set(newValue, forKey: Key.alwaysHiddenEnabled) }
    }

    static var showOnHover: Bool {
        get { defaults.bool(forKey: Key.showOnHover) }
        set { defaults.set(newValue, forKey: Key.showOnHover) }
    }

    static var soundTheme: SoundTheme {
        get {
            if let raw = defaults.string(forKey: Key.soundTheme), let theme = SoundTheme(rawValue: raw) { return theme }
            // Earlier builds had a simple on/off switch.
            return defaults.object(forKey: Key.playSounds) as? Bool == false ? .off : .pop
        }
        set { defaults.set(newValue.rawValue, forKey: Key.soundTheme) }
    }

    /// 0...1, relative to the system volume.
    static var soundVolume: Float {
        get { defaults.object(forKey: Key.soundVolume) as? Float ?? 0.35 }
        set { defaults.set(min(max(newValue, 0), 1), forKey: Key.soundVolume) }
    }

    /// Briefly reveal a hidden icon when its picture changes (needs Screen Recording).
    static var showChangedIcons: Bool {
        get { defaults.bool(forKey: Key.showChangedIcons) }
        set { defaults.set(newValue, forKey: Key.showChangedIcons) }
    }

    /// Icons that never get revealed when they change: identity key → display name.
    static var neverShowWhenChanged: [String: String] {
        get { defaults.dictionary(forKey: Key.neverShowWhenChanged) as? [String: String] ?? [:] }
        set { defaults.set(newValue, forKey: Key.neverShowWhenChanged) }
    }

    static var arrowStyle: ArrowStyle {
        get { defaults.string(forKey: Key.arrowStyle).flatMap(ArrowStyle.init(rawValue:)) ?? .chevron }
        set { defaults.set(newValue.rawValue, forKey: Key.arrowStyle) }
    }

    /// Global shortcuts: `HotKeyAction.id` → key combo.
    static var hotKeys: [String: KeyCombo] {
        get { decode([String: KeyCombo].self, Key.hotKeys) ?? [:] }
        set { encode(newValue, Key.hotKeys) }
    }

    static var revealMode: RevealMode {
        get { defaults.string(forKey: Key.revealMode).flatMap(RevealMode.init(rawValue:)) ?? .menuBar }
        set { defaults.set(newValue.rawValue, forKey: Key.revealMode) }
    }

    static var triggers: [TriggerRule] {
        get { decode([TriggerRule].self, Key.triggers) ?? [] }
        set { encode(newValue, Key.triggers) }
    }

    static var profiles: [Profile] {
        get { decode([Profile].self, Key.profiles) ?? [] }
        set { encode(newValue, Key.profiles) }
    }

    /// The profile applied last, if its settings haven't been changed since.
    static var activeProfile: UUID? {
        get { defaults.string(forKey: Key.activeProfile).flatMap(UUID.init(uuidString:)) }
        set { defaults.set(newValue?.uuidString, forKey: Key.activeProfile) }
    }

    /// Menu bar tint as "#RRGGBB"; nil = no tint.
    static var tintColor: String? {
        get { defaults.string(forKey: Key.tintColor) }
        set { defaults.set(newValue, forKey: Key.tintColor) }
    }

    static var tintOpacity: Double {
        get { defaults.object(forKey: Key.tintOpacity) as? Double ?? 0.25 }
        set { defaults.set(min(max(newValue, 0.05), 1), forKey: Key.tintOpacity) }
    }

    /// A thin line along the bottom of the menu bar.
    static var showBorder: Bool {
        get { defaults.bool(forKey: Key.showBorder) }
        set { defaults.set(newValue, forKey: Key.showBorder) }
    }

    /// Blank items the user can ⌘-drag between icons to group them.
    static var spacerCount: Int {
        get { defaults.integer(forKey: Key.spacerCount) }
        set { defaults.set(min(max(newValue, 0), 5), forKey: Key.spacerCount) }
    }

    static var itemSpacing: ItemSpacing {
        get { defaults.string(forKey: Key.itemSpacing).flatMap(ItemSpacing.init(rawValue:)) ?? .standard }
        set { defaults.set(newValue.rawValue, forKey: Key.itemSpacing) }
    }

    private static func decode<T: Decodable>(_ type: T.Type, _ key: String) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    private static func encode<T: Encodable>(_ value: T, _ key: String) {
        defaults.set(try? JSONEncoder().encode(value), forKey: key)
    }

    // MARK: - Backup

    /// Everything worth keeping, as a property list.
    static func exportData() throws -> Data {
        var values: [String: Any] = [:]
        for key in allKeys { values[key] = defaults.object(forKey: key) }
        for (key, value) in defaults.dictionaryRepresentation() where key.hasPrefix(positionKeyPrefix) {
            values[key] = value
        }
        let file: [String: Any] = ["format": "BarManager settings", "version": 1, "values": values]
        return try PropertyListSerialization.data(fromPropertyList: file, format: .xml, options: 0)
    }

    /// Replaces the current settings with an exported file's. Returns false if
    /// the file isn't a BarManager export.
    @discardableResult
    static func importData(_ data: Data) throws -> Bool {
        guard let file = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              file["format"] as? String == "BarManager settings",
              let values = file["values"] as? [String: Any] else { return false }
        resetAll()
        for (key, value) in values where allKeys.contains(key) || key.hasPrefix(positionKeyPrefix) {
            defaults.set(value, forKey: key)
        }
        defaults.set(true, forKey: Key.hasShownWelcome)
        return true
    }

    /// Back to defaults. Keeps the welcome flag and where items sit in the menu bar.
    static func resetAll() {
        for key in allKeys { defaults.removeObject(forKey: key) }
    }

    static var hasShownWelcome: Bool {
        get { defaults.bool(forKey: Key.hasShownWelcome) }
        set { defaults.set(newValue, forKey: Key.hasShownWelcome) }
    }
}

/// How clicking the arrow shows hidden icons.
enum RevealMode: String, CaseIterable, Codable {
    /// Right in the menu bar.
    case menuBar
    /// In a separate bar below the menu bar.
    case bar
    /// In the menu bar, or the separate bar when they wouldn't all fit.
    case automatic

    var title: String {
        switch self {
        case .menuBar: "In the Menu Bar"
        case .bar: "In a Bar Below the Menu Bar"
        case .automatic: "In the Menu Bar, or Below It When They Don’t Fit"
        }
    }
}

/// Space between menu bar icons (a macOS-wide setting).
enum ItemSpacing: String, CaseIterable, Codable {
    case standard, compact, tight, roomy

    var title: String {
        switch self {
        case .standard: "Standard"
        case .compact: "Compact"
        case .tight: "Tight"
        case .roomy: "Roomy"
        }
    }

    /// Points for NSStatusItemSpacing / NSStatusItemSelectionPadding; nil = macOS default.
    var points: Int? {
        switch self {
        case .standard: nil
        case .compact: 8
        case .tight: 4
        case .roomy: 20
        }
    }
}

/// Pairs of built-in macOS sounds played when icons show and hide.
enum SoundTheme: String, CaseIterable {
    case off, pop, bubble, glass, morse, purr, submarine, frog

    var title: String {
        switch self {
        case .off: "None"
        case .pop: "Pop"
        case .bubble: "Bubble"
        case .glass: "Glass"
        case .morse: "Morse"
        case .purr: "Purr"
        case .submarine: "Submarine"
        case .frog: "Frog"
        }
    }

    /// System sound names (from /System/Library/Sounds) for showing and hiding.
    var sounds: (show: String, hide: String)? {
        switch self {
        case .off: nil
        case .pop: ("Pop", "Tink")
        case .bubble: ("Bottle", "Pop")
        case .glass: ("Glass", "Ping")
        case .morse: ("Morse", "Morse")
        case .purr: ("Purr", "Funk")
        case .submarine: ("Submarine", "Blow")
        case .frog: ("Frog", "Hero")
        }
    }
}

/// SF Symbols used for the toggle, collapsed vs. expanded.
enum ArrowStyle: String, CaseIterable {
    case chevron, triangle, arrow, circle, dots, eye

    var title: String {
        switch self {
        case .chevron: "Chevron"
        case .triangle: "Triangle"
        case .arrow: "Arrow"
        case .circle: "Circle"
        case .dots: "Dots"
        case .eye: "Eye"
        }
    }

    var symbols: (collapsed: String, expanded: String) {
        switch self {
        case .chevron: ("chevron.left", "chevron.right")
        case .triangle: ("arrowtriangle.left.fill", "arrowtriangle.right.fill")
        case .arrow: ("arrow.left", "arrow.right")
        case .circle: ("chevron.left.circle", "chevron.right.circle.fill")
        case .dots: ("ellipsis.circle", "ellipsis.circle.fill")
        case .eye: ("eye.slash", "eye")
        }
    }
}
