import AppKit
import XCTest
@testable import BarManager

final class AppearanceTests: XCTestCase {
    /// Every sound a theme names must ship with macOS, or it silently plays nothing.
    func testSoundThemesUseSystemSounds() {
        for theme in SoundTheme.allCases {
            guard let sounds = theme.sounds else {
                XCTAssertEqual(theme, .off)
                continue
            }
            for name in [sounds.show, sounds.hide] {
                XCTAssertNotNil(NSSound(named: name), "\(theme): missing system sound \(name)")
            }
        }
    }

    func testSoundThemesAreDistinct() {
        let pairs = SoundTheme.allCases.compactMap(\.sounds).map { "\($0.show)/\($0.hide)" }
        XCTAssertEqual(Set(pairs).count, pairs.count, "two themes sound the same")
    }

    /// Every arrow style must resolve to real SF Symbols on the minimum macOS.
    func testArrowStylesUseExistingSymbols() {
        for style in ArrowStyle.allCases {
            for name in [style.symbols.collapsed, style.symbols.expanded] {
                XCTAssertNotNil(NSImage(systemSymbolName: name, accessibilityDescription: nil), "\(style): missing symbol \(name)")
            }
        }
    }

    func testSettingsRoundTripRawValues() {
        for theme in SoundTheme.allCases { XCTAssertEqual(SoundTheme(rawValue: theme.rawValue), theme) }
        for style in ArrowStyle.allCases { XCTAssertEqual(ArrowStyle(rawValue: style.rawValue), style) }
    }
}
