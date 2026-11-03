import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controller: MenuBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        controller = MenuBarController()

        if !Settings.hasShownWelcome {
            Settings.hasShownWelcome = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                MenuBarController.showHowTo()
            }
        }
    }
}
