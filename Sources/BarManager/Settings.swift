import Foundation

enum Settings {
    private static let defaults = UserDefaults.standard

    private enum Key {
        static let autoHideDelay = "autoHideDelay"
        static let isCollapsed = "isCollapsed"
        static let alwaysHiddenEnabled = "alwaysHiddenEnabled"
        static let hasShownWelcome = "hasShownWelcome"
        static let showOnHover = "showOnHover"
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
        get { defaults.object(forKey: Key.showOnHover) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Key.showOnHover) }
    }

    static var hasShownWelcome: Bool {
        get { defaults.bool(forKey: Key.hasShownWelcome) }
        set { defaults.set(newValue, forKey: Key.hasShownWelcome) }
    }
}
