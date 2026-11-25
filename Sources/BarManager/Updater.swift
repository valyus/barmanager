import AppKit
import Sparkle

/// In-app updates through Sparkle. Updates come from the appcast attached to
/// the latest GitHub release and must be signed with the key whose public half
/// is in Info.plist (`SUPublicEDKey`); builds without one never check.
final class Updater: NSObject, SPUUpdaterDelegate, SPUStandardUserDriverDelegate {
    static let shared = Updater()

    private var controller: SPUStandardUpdaterController?
    /// The version found by the last check, until it's installed or skipped.
    private(set) var availableVersion: String?
    /// Called when `availableVersion` changes, to update the arrow and menu.
    var onAvailabilityChange: (() -> Void)?

    /// False for builds that can't update themselves: run from `swift run`,
    /// or built without a public key.
    var isConfigured: Bool { controller != nil }

    func start() {
        guard controller == nil, Self.canUpdate(Bundle.main) else { return }
        controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: self, userDriverDelegate: self)
    }

    static func canUpdate(_ bundle: Bundle) -> Bool {
        guard bundle.bundleURL.pathExtension == "app",
              let key = bundle.object(forInfoDictionaryKey: "SUPublicEDKey") as? String, !key.isEmpty,
              bundle.object(forInfoDictionaryKey: "SUFeedURL") as? String != nil else { return false }
        return true
    }

    func checkForUpdates() {
        guard let controller else { return }
        NSApp.activate(ignoringOtherApps: true) // Sparkle's windows come to the front
        controller.checkForUpdates(nil)
    }

    var canCheckForUpdates: Bool { controller?.updater.canCheckForUpdates ?? false }

    var automaticallyChecks: Bool {
        get { controller?.updater.automaticallyChecksForUpdates ?? false }
        set { controller?.updater.automaticallyChecksForUpdates = newValue }
    }

    var automaticallyDownloads: Bool {
        get { controller?.updater.automaticallyDownloadsUpdates ?? false }
        set { controller?.updater.automaticallyDownloadsUpdates = newValue }
    }

    var lastCheck: Date? { controller?.updater.lastUpdateCheckDate }

    // MARK: - SPUUpdaterDelegate

    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        NSLog("BarManager: update \(item.displayVersionString) (build \(item.versionString)) is available")
        setAvailable(item.displayVersionString)
    }

    func updater(_ updater: SPUUpdater, didAbortWithError error: Error) {
        NSLog("BarManager: update check failed: \(error.localizedDescription)")
    }

    func updaterDidNotFindUpdate(_ updater: SPUUpdater) {
        setAvailable(nil)
    }

    func updater(_ updater: SPUUpdater, userDidMake choice: SPUUserUpdateChoice, forUpdate updateItem: SUAppcastItem, state: SPUUserUpdateState) {
        // Skipping clears the reminder; "Later" keeps it.
        if choice == .skip { setAvailable(nil) }
    }

    private func setAvailable(_ version: String?) {
        guard availableVersion != version else { return }
        availableVersion = version
        onAvailabilityChange?()
    }

    // MARK: - SPUStandardUserDriverDelegate

    /// BarManager has no Dock icon or main window, so a background check
    /// shouldn't throw a window in front of whatever you're doing. Sparkle
    /// shows it quietly; the arrow and the right-click menu point it out.
    var supportsGentleScheduledUpdateReminders: Bool { true }

    func standardUserDriverShouldHandleShowingScheduledUpdate(_ update: SUAppcastItem, andInImmediateFocus immediateFocus: Bool) -> Bool {
        immediateFocus
    }

    func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState) {
        setAvailable(update.displayVersionString)
    }

    func standardUserDriverDidReceiveUserAttention(forUpdate update: SUAppcastItem) {
        // Shown to the user; the menu item stays until it's installed or skipped.
    }

    func standardUserDriverWillFinishUpdateSession() {}
}
