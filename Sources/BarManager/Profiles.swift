import Foundation

/// A named set of settings to switch between, like "Work" or "Presenting".
struct Profile: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var settings: ProfileSettings
}

/// The settings a profile switches. Sections and icon positions stay as they
/// are: macOS keeps those for each app.
struct ProfileSettings: Codable, Equatable {
    var hideIcons: Bool
    var alwaysHiddenEnabled: Bool
    var autoHideDelay: TimeInterval
    var showOnHover: Bool
    var showChangedIcons: Bool
    var soundTheme: String
    var arrowStyle: String
    var revealMode: String
    var tintColor: String?
    var tintOpacity: Double
    var showBorder: Bool

    static func current(isCollapsed: Bool) -> ProfileSettings {
        ProfileSettings(
            hideIcons: isCollapsed,
            alwaysHiddenEnabled: Settings.alwaysHiddenEnabled,
            autoHideDelay: Settings.autoHideDelay,
            showOnHover: Settings.showOnHover,
            showChangedIcons: Settings.showChangedIcons,
            soundTheme: Settings.soundTheme.rawValue,
            arrowStyle: Settings.arrowStyle.rawValue,
            revealMode: Settings.revealMode.rawValue,
            tintColor: Settings.tintColor,
            tintOpacity: Settings.tintOpacity,
            showBorder: Settings.showBorder
        )
    }

    /// Writes these into Settings. The caller applies them to the menu bar.
    func store() {
        Settings.alwaysHiddenEnabled = alwaysHiddenEnabled
        Settings.autoHideDelay = autoHideDelay
        Settings.showOnHover = showOnHover
        Settings.showChangedIcons = showChangedIcons
        Settings.soundTheme = SoundTheme(rawValue: soundTheme) ?? .pop
        Settings.arrowStyle = ArrowStyle(rawValue: arrowStyle) ?? .chevron
        Settings.revealMode = RevealMode(rawValue: revealMode) ?? .menuBar
        Settings.tintColor = tintColor
        Settings.tintOpacity = tintOpacity
        Settings.showBorder = showBorder
    }

    /// Hides everything and keeps it quiet: no sounds, nothing popping up.
    static let presenting = ProfileSettings(
        hideIcons: true, alwaysHiddenEnabled: true, autoHideDelay: 5, showOnHover: false,
        showChangedIcons: false, soundTheme: SoundTheme.off.rawValue, arrowStyle: ArrowStyle.chevron.rawValue,
        revealMode: RevealMode.menuBar.rawValue, tintColor: nil, tintOpacity: 0.25, showBorder: false
    )
}
