import AppKit
import Carbon.HIToolbox
import XCTest
@testable import BarManager

final class HotKeyTests: XCTestCase {
    func testDisplayStringOrdersModifiersLikeMacOS() {
        let combo = KeyCombo(keyCode: UInt32(kVK_ANSI_B), modifiers: UInt32(cmdKey | optionKey | controlKey | shiftKey))
        XCTAssertEqual(combo.displayString, "⌃⌥⇧⌘B")
        XCTAssertEqual(KeyCombo(keyCode: UInt32(kVK_F5), modifiers: 0).displayString, "F5")
        XCTAssertEqual(KeyCombo(keyCode: UInt32(kVK_Space), modifiers: UInt32(optionKey)).displayString, "⌥Space")
    }

    func testActionIDsRoundTrip() {
        let profile = UUID()
        let actions: [HotKeyAction] = [.toggleHidden, .showAll, .search, .openItem("com.apple.controlcenter#Wi-Fi"), .applyProfile(profile)]
        for action in actions { XCTAssertEqual(HotKeyAction(id: action.id), action) }
        XCTAssertNil(HotKeyAction(id: "nonsense"))
        XCTAssertNil(HotKeyAction(id: "profile:not-a-uuid"))
    }

    func testComboEncodes() throws {
        let combo = KeyCombo(keyCode: 11, modifiers: UInt32(cmdKey))
        let data = try JSONEncoder().encode(["toggle": combo])
        XCTAssertEqual(try JSONDecoder().decode([String: KeyCombo].self, from: data)["toggle"], combo)
    }
}

final class SearchTests: XCTestCase {
    func testPrefixBeatsWordBeatsSubstringBeatsScattered() throws {
        let prefix = try XCTUnwrap(SearchMatcher.score("wi", "Wi‑Fi"))
        let word = try XCTUnwrap(SearchMatcher.score("wi", "Control Center – Wi‑Fi"))
        let substring = try XCTUnwrap(SearchMatcher.score("ox", "Dropbox"))
        let scattered = try XCTUnwrap(SearchMatcher.score("cc", "Control Center"))
        XCTAssertGreaterThan(prefix, word)
        XCTAssertGreaterThan(word, substring)
        XCTAssertGreaterThan(substring, scattered)
    }

    func testNoMatch() {
        XCTAssertNil(SearchMatcher.score("zz", "Battery"))
        XCTAssertNotNil(SearchMatcher.score("", "Battery"))
        XCTAssertNotNil(SearchMatcher.score("BAT", "battery"))
    }
}

final class TriggerTests: XCTestCase {
    func testConditions() {
        var state = SystemState()
        state.batteryPercent = 15
        state.onBatteryPower = true
        state.screenCount = 2
        state.runningBundleIDs = ["com.apple.Safari"]
        state.frontmostBundleID = "com.apple.Terminal"

        XCTAssertTrue(TriggerCondition.batteryBelow(percent: 20).isMet(in: state))
        XCTAssertFalse(TriggerCondition.batteryBelow(percent: 10).isMet(in: state))
        XCTAssertTrue(TriggerCondition.onBatteryPower.isMet(in: state))
        XCTAssertTrue(TriggerCondition.externalDisplayConnected.isMet(in: state))
        XCTAssertTrue(TriggerCondition.appRunning(bundleID: "com.apple.Safari", name: "Safari").isMet(in: state))
        XCTAssertFalse(TriggerCondition.appFrontmost(bundleID: "com.apple.Safari", name: "Safari").isMet(in: state))
        XCTAssertFalse(TriggerCondition.networkChanged.isMet(in: state), "events are never a lasting state")

        state.batteryPercent = nil // a desktop Mac
        XCTAssertFalse(TriggerCondition.batteryBelow(percent: 100).isMet(in: state))
    }

    func testWiFiNetwork() throws {
        var state = SystemState()
        let home = TriggerCondition.wifiNetwork(name: "Home")
        XCTAssertFalse(home.isMet(in: state), "no Wi‑Fi, or no Location Services permission")
        state.wifiNetwork = "Home"
        XCTAssertTrue(home.isMet(in: state))
        state.wifiNetwork = "home"
        XCTAssertFalse(home.isMet(in: state), "network names are case-sensitive")
        XCTAssertTrue(home.needsWiFi)
        XCTAssertFalse(home.isEvent)
        XCTAssertFalse(TriggerCondition.networkChanged.needsWiFi)

        let rule = TriggerRule(condition: home, action: .showHiddenIcons)
        let decoded = try JSONDecoder().decode(TriggerRule.self, from: JSONEncoder().encode(rule))
        XCTAssertEqual(decoded, rule)
    }

    func testTimeRangeWrapsPastMidnight() {
        var state = SystemState()
        let night = TriggerCondition.timeRange(start: 22 * 60, end: 7 * 60)
        let day = TriggerCondition.timeRange(start: 9 * 60, end: 17 * 60)
        state.minutesSinceMidnight = 23 * 60
        XCTAssertTrue(night.isMet(in: state))
        XCTAssertFalse(day.isMet(in: state))
        state.minutesSinceMidnight = 6 * 60 + 59
        XCTAssertTrue(night.isMet(in: state))
        state.minutesSinceMidnight = 9 * 60
        XCTAssertTrue(day.isMet(in: state))
        state.minutesSinceMidnight = 17 * 60
        XCTAssertFalse(day.isMet(in: state), "the end time is exclusive")
    }

    func testRulesEncode() throws {
        let rules = [
            TriggerRule(condition: .batteryBelow(percent: 20), action: .showHiddenIcons),
            TriggerRule(enabled: false, condition: .timeRange(start: 60, end: 120), action: .applyProfile(UUID())),
            TriggerRule(condition: .appFrontmost(bundleID: "a.b", name: "AB"), action: .showHiddenIcons),
        ]
        XCTAssertEqual(try JSONDecoder().decode([TriggerRule].self, from: JSONEncoder().encode(rules)), rules)
    }
}

final class SettingsBackupTests: XCTestCase {
    func testExportImportRoundTrip() throws {
        let defaults = UserDefaults.standard
        let saved = Settings.allKeys.map { ($0, defaults.object(forKey: $0)) }
        defer { for (key, value) in saved { defaults.set(value, forKey: key) } }

        Settings.autoHideDelay = 30
        Settings.spacerCount = 2
        Settings.profiles = [Profile(name: "Work", settings: .presenting)]
        Settings.hotKeys = ["search": KeyCombo(keyCode: 49, modifiers: UInt32(optionKey))]
        let data = try Settings.exportData()

        Settings.resetAll()
        XCTAssertEqual(Settings.autoHideDelay, 10)
        XCTAssertTrue(Settings.profiles.isEmpty)

        XCTAssertTrue(try Settings.importData(data))
        XCTAssertEqual(Settings.autoHideDelay, 30)
        XCTAssertEqual(Settings.spacerCount, 2)
        XCTAssertEqual(Settings.profiles.first?.name, "Work")
        XCTAssertEqual(Settings.hotKeys["search"]?.keyCode, 49)
    }

    func testImportRejectsOtherFiles() throws {
        let other = try PropertyListSerialization.data(fromPropertyList: ["hello": "world"], format: .xml, options: 0)
        XCTAssertFalse(try Settings.importData(other))
    }

    func testTintHexRoundTrip() {
        let color = MenuBarTint.color(fromHex: "#0A84FF")
        XCTAssertNotNil(color)
        XCTAssertEqual(color.map(MenuBarTint.hex(from:)), "#0A84FF")
        XCTAssertNil(MenuBarTint.color(fromHex: "blue"))
    }

    func testPresentingProfileIsQuiet() {
        XCTAssertTrue(ProfileSettings.presenting.hideIcons)
        XCTAssertFalse(ProfileSettings.presenting.showChangedIcons)
        XCTAssertEqual(ProfileSettings.presenting.soundTheme, SoundTheme.off.rawValue)
    }
}

final class UpdaterTests: XCTestCase {
    /// The test runner isn't an app with a signing key, so it must never check.
    func testBuildsWithoutAKeyDontUpdate() {
        XCTAssertFalse(Updater.canUpdate(Bundle.main))
        XCTAssertFalse(Updater.shared.isConfigured)
    }
}
