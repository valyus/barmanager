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
    }

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

    static var hasShownWelcome: Bool {
        get { defaults.bool(forKey: Key.hasShownWelcome) }
        set { defaults.set(newValue, forKey: Key.hasShownWelcome) }
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
