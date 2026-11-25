import CoreLocation
import CoreWLAN

/// The name of the Wi‑Fi network the Mac is on. macOS hands it only to apps
/// allowed to use Location Services, so this also asks for that permission.
final class WiFi: NSObject, CLLocationManagerDelegate {
    static let shared = WiFi()

    /// Called on the main thread when the permission is granted or refused.
    var onPermissionChange: (() -> Void)?

    private let manager = CLLocationManager()
    private var waiting: [() -> Void] = []

    private override init() {
        super.init()
        manager.delegate = self
    }

    /// nil when not on Wi‑Fi, or when Location Services isn't allowed.
    var currentNetwork: String? { CWWiFiClient.shared().interface()?.ssid() }

    var hasPermission: Bool {
        manager.authorizationStatus == .authorizedAlways // what "allowed" is on macOS
    }

    var isRefused: Bool {
        let status = manager.authorizationStatus
        return status == .denied || status == .restricted
    }

    /// Asks once; afterwards the answer stands until changed in System Settings.
    func requestPermission(then done: @escaping () -> Void = {}) {
        guard manager.authorizationStatus == .notDetermined else { done(); return }
        waiting.append(done)
        manager.requestWhenInUseAuthorization()
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard manager.authorizationStatus != .notDetermined else { return }
        let callbacks = waiting
        waiting = []
        callbacks.forEach { $0() }
        onPermissionChange?()
    }
}
