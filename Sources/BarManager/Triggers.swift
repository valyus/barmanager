import AppKit
import IOKit.ps
import Network

/// "When <condition>, <action>."
struct TriggerRule: Codable, Identifiable, Equatable {
    var id = UUID()
    var enabled = true
    var condition: TriggerCondition
    var action: TriggerAction
}

enum TriggerCondition: Codable, Equatable {
    case batteryBelow(percent: Int)
    case onBatteryPower
    case externalDisplayConnected
    case appRunning(bundleID: String, name: String)
    case appFrontmost(bundleID: String, name: String)
    /// Minutes since midnight; may wrap past midnight (22:00–07:00).
    case timeRange(start: Int, end: Int)
    /// A moment, not a state: the network connection changed (Wi-Fi, VPN, cable).
    case networkChanged
    /// Connected to the Wi‑Fi network with this name.
    case wifiNetwork(name: String)

    /// Events last only a moment; states last as long as they're true.
    var isEvent: Bool { self == .networkChanged }

    /// Reading the Wi‑Fi name needs Location Services, so it's only read when a rule uses it.
    var needsWiFi: Bool {
        if case .wifiNetwork = self { return true }
        return false
    }

    func isMet(in state: SystemState) -> Bool {
        switch self {
        case .batteryBelow(let percent):
            guard let battery = state.batteryPercent else { return false }
            return battery < percent
        case .onBatteryPower:
            return state.onBatteryPower
        case .externalDisplayConnected:
            return state.screenCount > 1
        case .appRunning(let bundleID, _):
            return state.runningBundleIDs.contains(bundleID)
        case .appFrontmost(let bundleID, _):
            return state.frontmostBundleID == bundleID
        case .timeRange(let start, let end):
            let now = state.minutesSinceMidnight
            return start <= end ? (now >= start && now < end) : (now >= start || now < end)
        case .networkChanged:
            return false
        case .wifiNetwork(let name):
            return state.wifiNetwork == name
        }
    }

    var title: String {
        switch self {
        case .batteryBelow(let percent): "Battery is below \(percent)%"
        case .onBatteryPower: "Running on battery"
        case .externalDisplayConnected: "An external display is connected"
        case .appRunning(_, let name): "\(name) is open"
        case .appFrontmost(_, let name): "\(name) is in front"
        case .timeRange(let start, let end): "Between \(Self.clock(start)) and \(Self.clock(end))"
        case .networkChanged: "The network changes"
        case .wifiNetwork(let name): "Connected to the Wi‑Fi network “\(name)”"
        }
    }

    static func clock(_ minutes: Int) -> String {
        String(format: "%02d:%02d", (minutes / 60) % 24, minutes % 60)
    }
}

enum TriggerAction: Codable, Equatable {
    /// Show the hidden icons (for a moment after an event, or while a state lasts).
    case showHiddenIcons
    /// Switch to a profile when the condition starts.
    case applyProfile(UUID)

    func title(profiles: [Profile]) -> String {
        switch self {
        case .showHiddenIcons: "Show hidden icons"
        case .applyProfile(let id): "Switch to “\(profiles.first { $0.id == id }?.name ?? "Missing profile")”"
        }
    }
}

/// What the conditions are checked against.
struct SystemState: Equatable {
    var batteryPercent: Int?
    var onBatteryPower = false
    var screenCount = 1
    var runningBundleIDs: Set<String> = []
    var frontmostBundleID: String?
    var minutesSinceMidnight = 0
    var wifiNetwork: String?

    static func now(includeWiFi: Bool = false) -> SystemState {
        var state = SystemState()
        if let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
           let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] {
            for source in list {
                guard let description = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                      description[kIOPSTypeKey] as? String == kIOPSInternalBatteryType else { continue }
                if let current = description[kIOPSCurrentCapacityKey] as? Int,
                   let max = description[kIOPSMaxCapacityKey] as? Int, max > 0 {
                    state.batteryPercent = current * 100 / max
                }
                state.onBatteryPower = description[kIOPSPowerSourceStateKey] as? String == kIOPSBatteryPowerValue
            }
        }
        state.screenCount = NSScreen.screens.count
        state.runningBundleIDs = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        state.frontmostBundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        let parts = Calendar.current.dateComponents([.hour, .minute], from: Date())
        state.minutesSinceMidnight = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
        if includeWiFi { state.wifiNetwork = WiFi.shared.currentNetwork }
        return state
    }
}

/// Watches the system and tells the controller when rules start and stop.
final class TriggerEngine {
    /// A rule's condition became true (or its event happened).
    var onStart: ((TriggerRule) -> Void)?
    /// A state rule's condition stopped being true.
    var onEnd: ((TriggerRule) -> Void)?

    private var active: Set<UUID> = []
    private var timer: Timer?
    private var observers: [NSObjectProtocol] = []
    private var pathMonitor: NWPathMonitor?
    private var lastPath: String?

    func start() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in self?.evaluate() }
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification,
                     NSWorkspace.didActivateApplicationNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in self?.evaluate() })
        }
        observers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.evaluate() })

        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            let summary = "\(path.status)|" + path.availableInterfaces.map(\.name).joined(separator: ",")
            DispatchQueue.main.async { self?.pathChanged(summary) }
        }
        monitor.start(queue: .global(qos: .utility))
        pathMonitor = monitor
        WiFi.shared.onPermissionChange = { [weak self] in self?.evaluate() }
        evaluate()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        observers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0); NotificationCenter.default.removeObserver($0) }
        observers = []
        pathMonitor?.cancel()
        pathMonitor = nil
        lastPath = nil
        // End anything still running so nothing stays open.
        let rules = Settings.triggers
        for id in active { if let rule = rules.first(where: { $0.id == id }) { onEnd?(rule) } }
        active = []
    }

    /// Call after rules change.
    func rulesChanged() {
        let rules = Settings.triggers.filter(\.enabled)
        if rules.isEmpty { stop() } else { start(); evaluate() }
    }

    private func pathChanged(_ summary: String) {
        defer { lastPath = summary }
        guard let lastPath, lastPath != summary else { return } // the first report is just the current state
        evaluate() // the Wi‑Fi network may have changed
        for rule in Settings.triggers where rule.enabled && rule.condition == .networkChanged {
            onStart?(rule)
        }
    }

    func evaluate() {
        let rules = Settings.triggers.filter { $0.enabled && !$0.condition.isEvent }
        let state = SystemState.now(includeWiFi: rules.contains { $0.condition.needsWiFi })
        let ids = Set(rules.map(\.id))
        // Rules that were removed or turned off end now.
        let all = Settings.triggers
        for id in active.subtracting(ids) {
            active.remove(id)
            if let rule = all.first(where: { $0.id == id }) { onEnd?(rule) } else { onEnd?(TriggerRule(id: id, condition: .onBatteryPower, action: .showHiddenIcons)) }
        }
        for rule in rules {
            let met = rule.condition.isMet(in: state)
            if met, active.insert(rule.id).inserted {
                onStart?(rule)
            } else if !met, active.remove(rule.id) != nil {
                onEnd?(rule)
            }
        }
    }
}
