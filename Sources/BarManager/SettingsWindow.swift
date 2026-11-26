import AppKit
import Carbon.HIToolbox
import ServiceManagement
import SwiftUI
import UniformTypeIdentifiers

enum SettingsTab: String, CaseIterable, Identifiable {
    case general, shortcuts, icons, triggers, profiles, appearance, backup
    var id: String { rawValue }
}

/// The settings window. One instance; reopening brings it to the front.
final class SettingsWindowController: NSObject, NSWindowDelegate {
    static let shared = SettingsWindowController()

    private var window: NSWindow?
    private let model = SettingsModel()

    func show(tab: SettingsTab) {
        model.tab = tab
        model.revision += 1
        if window == nil {
            // Wide enough for all seven tabs; narrower and macOS hides every one of them under ».
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 820, height: 560),
                                  styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
            window.title = "BarManager Settings"
            window.isReleasedWhenClosed = false
            window.contentViewController = NSHostingController(rootView: SettingsView(model: model))
            window.setContentSize(NSSize(width: 820, height: 560))
            window.contentMinSize = NSSize(width: 800, height: 420)
            window.center()
            window.delegate = self
            self.window = window
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        if tab == .icons { model.loadIcons() }
    }

    /// Re-reads Settings after they changed elsewhere (the menu, a profile).
    func refresh() {
        guard window?.isVisible == true else { return }
        model.revision += 1
    }

    func windowWillClose(_ notification: Notification) {
        HotKeyCenter.shared.isPaused = false
    }
}

final class SettingsModel: ObservableObject {
    @Published var tab: SettingsTab = .general
    /// Bumped to make views re-read Settings.
    @Published var revision = 0
    @Published var icons: [PicturedEntry] = []
    @Published var loadingIcons = false
    @Published var recording: String?
    /// The icon being moved right now, by key.
    @Published var movingKey: String?
    @Published var moveMessage: String?

    /// A two-way binding straight onto a Settings property.
    func bind<T>(_ get: @escaping () -> T, _ set: @escaping (T) -> Void) -> Binding<T> {
        Binding(get: { _ = self.revision; return get() }, set: { set($0); self.changed() })
    }

    /// Settings changed here; apply them to the menu bar.
    func changed() {
        revision += 1
        NotificationCenter.default.post(name: MenuBarController.settingsChanged, object: nil)
    }

    func loadIcons() {
        guard AXIsProcessTrusted() else { return }
        loadingIcons = true
        MenuBarCatalog.load { [weak self] entries in
            guard let self else { return }
            let pictured = AppBridge.controller?.picturedEntries(entries) ?? []
            let order: [MenuBarSection] = [.visible, .hidden, .alwaysHidden]
            // Right to left within each section, as they appear from the arrow;
            // icons macOS has no room for last.
            self.icons = pictured.sorted {
                if $0.hasRoom != $1.hasRoom { return $0.hasRoom }
                let a = order.firstIndex(of: $0.section)!, b = order.firstIndex(of: $1.section)!
                return a != b ? a < b : $0.entry.frame.minX > $1.entry.frame.minX
            }
            self.loadingIcons = false
        }
    }

    func move(_ item: PicturedEntry, to section: MenuBarSection) {
        guard movingKey == nil, item.section != section, let controller = AppBridge.controller else { return }
        movingKey = item.entry.key
        moveMessage = nil
        controller.move(item.entry, to: section) { [weak self] result in
            guard let self else { return }
            self.movingKey = nil
            switch result {
            case .moved: break
            case .noRoom:
                self.moveMessage = "Couldn’t move “\(item.entry.name)”: it or its new spot is behind the notch or off screen. Quit an app with menu bar icons, or ⌘-drag it by hand."
            case .failed:
                self.moveMessage = "Couldn’t move “\(item.entry.name)”. Some icons can’t be moved; try ⌘-dragging it in the menu bar."
            case .needsAccessibility:
                self.moveMessage = "Moving icons needs Accessibility permission."
            }
            self.loadIcons()
        }
    }

    func setShortcut(_ combo: KeyCombo?, for actionID: String) {
        var keys = Settings.hotKeys
        if let combo {
            // One shortcut, one job.
            for (id, existing) in keys where existing == combo { keys[id] = nil }
        }
        keys[actionID] = combo
        Settings.hotKeys = keys
        changed()
    }
}

private struct SettingsView: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        TabView(selection: $model.tab) {
            GeneralTab(model: model).tabItem { Label("General", systemImage: "gearshape") }.tag(SettingsTab.general)
            ShortcutsTab(model: model).tabItem { Label("Shortcuts", systemImage: "command") }.tag(SettingsTab.shortcuts)
            IconsTab(model: model).tabItem { Label("Icons", systemImage: "menubar.rectangle") }.tag(SettingsTab.icons)
            TriggersTab(model: model).tabItem { Label("Triggers", systemImage: "bolt") }.tag(SettingsTab.triggers)
            ProfilesTab(model: model).tabItem { Label("Profiles", systemImage: "person.crop.rectangle.stack") }.tag(SettingsTab.profiles)
            AppearanceTab(model: model).tabItem { Label("Appearance", systemImage: "paintbrush") }.tag(SettingsTab.appearance)
            BackupTab(model: model).tabItem { Label("Backup", systemImage: "externaldrive") }.tag(SettingsTab.backup)
        }
        .padding()
        .frame(minWidth: 800, minHeight: 420)
    }
}

// MARK: - General

private struct GeneralTab: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        Form {
            Section("Showing hidden icons") {
                Picker("Show hidden icons", selection: model.bind({ Settings.revealMode }, { Settings.revealMode = $0 })) {
                    ForEach(RevealMode.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                Picker("Hide again after", selection: model.bind({ Settings.autoHideDelay }, { Settings.autoHideDelay = $0 })) {
                    Text("Never").tag(0.0)
                    Text("5 seconds").tag(5.0)
                    Text("10 seconds").tag(10.0)
                    Text("30 seconds").tag(30.0)
                    Text("1 minute").tag(60.0)
                }
                Toggle("Show hidden icons on hover", isOn: model.bind({ Settings.showOnHover }, { Settings.showOnHover = $0 }))
                Toggle("Briefly show hidden icons that change", isOn: model.bind({ Settings.showChangedIcons }, {
                    Settings.showChangedIcons = $0
                    if $0, !ChangeWatcher.hasPermission { ChangeWatcher.requestPermission() }
                }))
                Toggle("“Always Hidden” section", isOn: model.bind({ Settings.alwaysHiddenEnabled }, { Settings.alwaysHiddenEnabled = $0 }))
            }
            Section("Sound") {
                Picker("Sound", selection: model.bind({ Settings.soundTheme }, { Settings.soundTheme = $0; Self.preview() })) {
                    ForEach(SoundTheme.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                Slider(value: model.bind({ Double(Settings.soundVolume) }, { Settings.soundVolume = Float($0) }), in: 0.05...1) {
                    Text("Volume")
                } onEditingChanged: { editing in if !editing { Self.preview() } }
            }
            Section("Updates") {
                if Updater.shared.isConfigured {
                    Toggle("Check for updates automatically", isOn: model.bind({ Updater.shared.automaticallyChecks }, { Updater.shared.automaticallyChecks = $0 }))
                    Toggle("Download and install updates automatically", isOn: model.bind({ Updater.shared.automaticallyDownloads }, { Updater.shared.automaticallyDownloads = $0 }))
                        .disabled(!Updater.shared.automaticallyChecks)
                    HStack {
                        if let version = Updater.shared.availableVersion {
                            Text("BarManager \(version) is available.")
                        } else if let last = Updater.shared.lastCheck {
                            Text("Last checked \(last.formatted(.relative(presentation: .named))).").foregroundStyle(.secondary)
                        } else {
                            Text("Not checked yet.").foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button(Updater.shared.availableVersion == nil ? "Check Now" : "Install…") { Updater.shared.checkForUpdates() }
                    }
                } else {
                    Text("This copy of BarManager can’t update itself. Download new versions from GitHub.")
                        .foregroundStyle(.secondary)
                }
            }
            Section("Startup") {
                Toggle("Launch at login", isOn: model.bind({ SMAppService.mainApp.status == .enabled }, { on in
                    do { try on ? SMAppService.mainApp.register() : SMAppService.mainApp.unregister() } catch {
                        NSLog("BarManager: Launch at Login failed: \(error.localizedDescription)")
                    }
                }))
            }
            Section("Permissions") {
                PermissionRow(title: "Accessibility", detail: "App names, search, shortcuts for icons, the bar below the menu bar",
                              granted: AXIsProcessTrusted(), anchor: "Privacy_Accessibility")
                PermissionRow(title: "Screen Recording", detail: "Showing icons that change, pictures of icons",
                              granted: ChangeWatcher.hasPermission, anchor: "Privacy_ScreenCapture")
                if Settings.triggers.contains(where: { $0.condition.needsWiFi }) {
                    PermissionRow(title: "Location Services", detail: "Wi‑Fi network triggers (macOS treats the Wi‑Fi name as location)",
                                  granted: WiFi.shared.hasPermission, anchor: "Privacy_LocationServices")
                }
            }
        }
        .formStyle(.grouped)
    }

    static func preview() {
        guard let names = Settings.soundTheme.sounds, let sound = NSSound(named: names.show) else { return }
        sound.volume = Settings.soundVolume
        sound.play()
    }
}

private struct PermissionRow: View {
    let title: String
    let detail: String
    let granted: Bool
    let anchor: String

    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(title)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if granted {
                Label("Allowed", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
            } else {
                Button("Allow…") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)") {
                        NSWorkspace.shared.open(url)
                    }
                }
            }
        }
    }
}

// MARK: - Shortcuts

private struct ShortcutsTab: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        Form {
            Section {
                LabeledContent("Show or hide hidden icons") { ShortcutRecorder(model: model, actionID: HotKeyAction.toggleHidden.id) }
                LabeledContent("Show all, including “Always Hidden”") { ShortcutRecorder(model: model, actionID: HotKeyAction.showAll.id) }
                LabeledContent("Search menu bar icons") { ShortcutRecorder(model: model, actionID: HotKeyAction.search.id) }
            } footer: {
                Text("Shortcuts work in any app. Set shortcuts for single icons under Icons, and for profiles under Profiles.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

/// Click, then press the shortcut. Esc cancels; Delete clears.
struct ShortcutRecorder: View {
    @ObservedObject var model: SettingsModel
    let actionID: String
    @State private var monitor: Any?

    var body: some View {
        let _ = model.revision
        let combo = Settings.hotKeys[actionID]
        let recording = model.recording == actionID
        HStack(spacing: 4) {
            Button(recording ? "Type a shortcut…" : (combo?.displayString ?? "Record Shortcut")) {
                recording ? stop() : start()
            }
            .frame(minWidth: 130)
            if combo != nil, !recording {
                Button { model.setShortcut(nil, for: actionID) } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.borderless)
                    .help("Remove shortcut")
            }
        }
        .onDisappear { if recording { stop() } }
    }

    private func start() {
        model.recording = actionID
        HotKeyCenter.shared.isPaused = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let plain = event.modifierFlags.intersection([.command, .option, .control, .shift]).isEmpty
            if event.keyCode == UInt16(kVK_Escape), plain {
                stop()
            } else if event.keyCode == UInt16(kVK_Delete) || event.keyCode == UInt16(kVK_ForwardDelete), plain {
                model.setShortcut(nil, for: actionID)
                stop()
            } else if let combo = KeyCombo(event: event) {
                model.setShortcut(combo, for: actionID)
                stop()
            } else {
                NSSound.beep() // needs ⌘, ⌥ or ⌃
            }
            return nil
        }
    }

    private func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        if model.recording == actionID { model.recording = nil }
        HotKeyCenter.shared.isPaused = false
    }
}

// MARK: - Icons

private struct IconsTab: View {
    @ObservedObject var model: SettingsModel

    /// Always Hidden is offered only while that section is turned on.
    private func sections(including current: MenuBarSection) -> [MenuBarSection] {
        [.visible, .hidden, .alwaysHidden].filter { $0 != .alwaysHidden || Settings.alwaysHiddenEnabled || current == .alwaysHidden }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !AXIsProcessTrusted() {
                Text("BarManager needs Accessibility permission to list menu bar icons.")
                Button("Open Accessibility Settings…") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                        NSWorkspace.shared.open(url)
                    }
                }
                Spacer()
            } else {
                HStack {
                    Text("Every menu bar icon, nearest the arrow first. Choose a section to move an icon there, or ⌘-drag icons in the menu bar.")
                        .font(.callout).foregroundStyle(.secondary)
                    Spacer()
                    Button { model.loadIcons() } label: { Label("Reload", systemImage: "arrow.clockwise") }
                        .disabled(model.loadingIcons)
                }
                Table(model.icons, columns: {
                    TableColumn("Icon") { item in
                        HStack {
                            if let image = item.image {
                                Image(nsImage: image).resizable().aspectRatio(contentMode: .fit).frame(width: 30, height: 16)
                            }
                            Text(item.entry.name).lineLimit(1)
                        }
                    }
                    .width(min: 160, ideal: 220)
                    TableColumn("Section") { item in
                        if !item.hasRoom {
                            Text("No room").foregroundStyle(.secondary)
                                .help("macOS has no room to draw this icon, so it can’t be shown or opened. Quit an app with menu bar icons, or move icons you rarely need out of the way.")
                        } else if model.movingKey == item.entry.key {
                            HStack(spacing: 4) { ProgressView().controlSize(.small); Text("Moving…").foregroundStyle(.secondary) }
                        } else {
                            Picker("", selection: Binding(get: { item.section }, set: { model.move(item, to: $0) })) {
                                ForEach(sections(including: item.section), id: \.self) { Text($0.title).tag($0) }
                            }
                            .labelsHidden()
                            .disabled(model.movingKey != nil)
                            .help("Move this icon to another section")
                        }
                    }
                    .width(min: 120, ideal: 130)
                    TableColumn("Never pop up") { item in
                        Toggle("", isOn: model.bind({ Settings.neverShowWhenChanged[item.entry.key] != nil }, { on in
                            Settings.neverShowWhenChanged[item.entry.key] = on ? item.entry.name : nil
                        }))
                        .labelsHidden()
                        .help("Never show this icon when it changes")
                    }
                    .width(90)
                    TableColumn("Shortcut") { item in
                        ShortcutRecorder(model: model, actionID: HotKeyAction.openItem(item.entry.key).id)
                    }
                    .width(min: 150, ideal: 170)
                })
                .overlay { if model.icons.isEmpty { Text(model.loadingIcons ? "Finding icons…" : "No icons found").foregroundStyle(.secondary) } }
                if let message = model.moveMessage {
                    Text(message).font(.callout).foregroundStyle(.red)
                }
            }
        }
        .onAppear { if model.icons.isEmpty { model.loadIcons() } }
        .onDisappear { model.moveMessage = nil }
    }
}

extension PicturedEntry: Identifiable {
    var id: String { entry.key + "@\(Int(entry.frame.minX))" }
}

// MARK: - Triggers

private enum ConditionKind: String, CaseIterable, Identifiable {
    case battery, onBattery, display, appRunning, appFrontmost, time, wifi, network
    var id: String { rawValue }
    var title: String {
        switch self {
        case .battery: "Battery is below…"
        case .onBattery: "Running on battery"
        case .display: "An external display is connected"
        case .appRunning: "An app is open"
        case .appFrontmost: "An app is in front"
        case .time: "During certain hours"
        case .wifi: "Connected to a Wi‑Fi network"
        case .network: "The network changes"
        }
    }
}

private struct TriggersTab: View {
    @ObservedObject var model: SettingsModel
    @State private var kind: ConditionKind = .battery
    @State private var percent = 20
    @State private var appID = ""
    @State private var start = Calendar.current.date(from: DateComponents(hour: 9)) ?? Date()
    @State private var end = Calendar.current.date(from: DateComponents(hour: 17)) ?? Date()
    @State private var profileID = ""
    @State private var network = ""

    private var apps: [(id: String, name: String)] {
        let running = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular }
        var seen = Set<String>()
        return running.compactMap { app in
            guard let id = app.bundleIdentifier, seen.insert(id).inserted else { return nil }
            return (id, app.localizedName ?? id)
        }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        let _ = model.revision
        let rules = Settings.triggers
        let profiles = Settings.profiles
        Form {
            Section {
                if rules.isEmpty {
                    Text("No triggers yet.").foregroundStyle(.secondary)
                }
                ForEach(rules) { rule in
                    HStack {
                        Toggle("", isOn: model.bind({ rule.enabled }, { on in
                            Settings.triggers = Settings.triggers.map { $0.id == rule.id ? TriggerRule(id: $0.id, enabled: on, condition: $0.condition, action: $0.action) : $0 }
                        }))
                        .labelsHidden()
                        VStack(alignment: .leading) {
                            Text("When \(rule.condition.title.lowercasedFirst)")
                            Text(rule.action.title(profiles: profiles) + (rule.condition.isEvent || rule.action != .showHiddenIcons ? "" : " while it lasts"))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button(role: .destructive) {
                            Settings.triggers.removeAll { $0.id == rule.id }
                            model.changed()
                        } label: { Image(systemName: "trash") }
                            .buttonStyle(.borderless)
                    }
                }
            } header: {
                Text("Triggers")
            } footer: {
                Text("Triggers show the hidden icons or switch profiles on their own, for example while you’re on battery or when a VPN connects.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("New trigger") {
                Picker("When", selection: $kind) {
                    ForEach(ConditionKind.allCases) { Text($0.title).tag($0) }
                }
                switch kind {
                case .battery:
                    Stepper("Below \(percent)%", value: $percent, in: 5...95, step: 5)
                case .appRunning, .appFrontmost:
                    Picker("App", selection: $appID) {
                        Text("Choose…").tag("")
                        ForEach(apps, id: \.id) { Text($0.name).tag($0.id) }
                    }
                case .time:
                    DatePicker("From", selection: $start, displayedComponents: .hourAndMinute)
                    DatePicker("Until", selection: $end, displayedComponents: .hourAndMinute)
                case .wifi:
                    HStack {
                        TextField("Network", text: $network, prompt: Text("Wi‑Fi name"))
                        Button("Use Current") {
                            WiFi.shared.requestPermission {
                                if let current = WiFi.shared.currentNetwork { network = current }
                                model.changed()
                            }
                        }
                    }
                    if WiFi.shared.isRefused {
                        Text("macOS shows Wi‑Fi names only to apps allowed to use Location Services. Allow BarManager in System Settings → Privacy & Security → Location Services, or this trigger never starts.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                default:
                    EmptyView()
                }
                Picker("Then", selection: $profileID) {
                    Text("Show hidden icons").tag("")
                    ForEach(profiles) { Text("Switch to “\($0.name)”").tag($0.id.uuidString) }
                }
                HStack {
                    Spacer()
                    Button("Add Trigger") { add() }
                        .disabled((kind == .appRunning || kind == .appFrontmost) && appID.isEmpty
                                  || kind == .wifi && network.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            if network.isEmpty, WiFi.shared.hasPermission { network = WiFi.shared.currentNetwork ?? "" }
        }
    }

    private func add() {
        let condition: TriggerCondition
        let name = apps.first { $0.id == appID }?.name ?? appID
        switch kind {
        case .battery: condition = .batteryBelow(percent: percent)
        case .onBattery: condition = .onBatteryPower
        case .display: condition = .externalDisplayConnected
        case .appRunning: condition = .appRunning(bundleID: appID, name: name)
        case .appFrontmost: condition = .appFrontmost(bundleID: appID, name: name)
        case .time: condition = .timeRange(start: Self.minutes(start), end: Self.minutes(end))
        case .network: condition = .networkChanged
        case .wifi:
            condition = .wifiNetwork(name: network.trimmingCharacters(in: .whitespaces))
            WiFi.shared.requestPermission { model.changed() }
        }
        let action: TriggerAction = UUID(uuidString: profileID).map { .applyProfile($0) } ?? .showHiddenIcons
        Settings.triggers.append(TriggerRule(condition: condition, action: action))
        model.changed()
    }

    private static func minutes(_ date: Date) -> Int {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
        return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
    }
}

private extension String {
    var lowercasedFirst: String { prefix(1).lowercased() + dropFirst() }
}

// MARK: - Profiles

private struct ProfilesTab: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        let _ = model.revision
        let profiles = Settings.profiles
        let current = AppBridge.controller?.currentProfileID()
        Form {
            Section {
                if profiles.isEmpty {
                    Text("No profiles yet. Set things up the way you like, then save them as a profile.").foregroundStyle(.secondary)
                }
                ForEach(profiles) { profile in
                    HStack {
                        Image(systemName: profile.id == current ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(profile.id == current ? Color.accentColor : .secondary)
                        TextField("Name", text: model.bind({ profile.name }, { name in
                            Settings.profiles = Settings.profiles.map { $0.id == profile.id ? Profile(id: $0.id, name: name, settings: $0.settings) : $0 }
                        }))
                        .labelsHidden()
                        .frame(maxWidth: 160)
                        Spacer()
                        ShortcutRecorder(model: model, actionID: HotKeyAction.applyProfile(profile.id).id)
                        Button("Apply") { AppBridge.controller?.applyProfile(profile.id); model.revision += 1 }
                        Menu {
                            Button("Update with Current Settings") {
                                guard let settings = AppBridge.controller?.currentProfileSettings() else { return }
                                Settings.profiles = Settings.profiles.map { $0.id == profile.id ? Profile(id: $0.id, name: $0.name, settings: settings) : $0 }
                                model.changed()
                            }
                            Button("Delete", role: .destructive) {
                                Settings.profiles.removeAll { $0.id == profile.id }
                                Settings.hotKeys[HotKeyAction.applyProfile(profile.id).id] = nil
                                Settings.triggers.removeAll { $0.action == .applyProfile(profile.id) }
                                model.changed()
                            }
                        } label: { Image(systemName: "ellipsis.circle") }
                            .menuStyle(.borderlessButton)
                            .fixedSize()
                    }
                }
            } header: {
                Text("Profiles")
            } footer: {
                Text("A profile switches whether icons are hidden, auto-hide, hover, change alerts, sound, arrow style, where hidden icons show and the menu bar tint. Where icons sit stays the same.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section {
                HStack {
                    Button("Save Current Settings as Profile") {
                        guard let settings = AppBridge.controller?.currentProfileSettings() else { return }
                        let profile = Profile(name: "Profile \(Settings.profiles.count + 1)", settings: settings)
                        Settings.profiles.append(profile)
                        Settings.activeProfile = profile.id
                        model.changed()
                    }
                    Button("Add “Presenting” Profile") {
                        Settings.profiles.append(Profile(name: "Presenting", settings: .presenting))
                        model.changed()
                    }
                    .help("Hides everything, no sounds, nothing pops up")
                }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Appearance

private struct AppearanceTab: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        Form {
            Section("Arrow") {
                Picker("Arrow icon", selection: model.bind({ Settings.arrowStyle }, { Settings.arrowStyle = $0 })) {
                    ForEach(ArrowStyle.allCases, id: \.self) { style in
                        Label(style.title, systemImage: style.symbols.collapsed).tag(style)
                    }
                }
            }
            Section {
                Toggle("Tint the menu bar", isOn: model.bind({ Settings.tintColor != nil }, { Settings.tintColor = $0 ? "#0A84FF" : nil }))
                if Settings.tintColor != nil {
                    ColorPicker("Tint color", selection: model.bind({
                        Color(nsColor: MenuBarTint.color(fromHex: Settings.tintColor) ?? .systemBlue)
                    }, { Settings.tintColor = MenuBarTint.hex(from: NSColor($0)) }), supportsOpacity: false)
                    Slider(value: model.bind({ Settings.tintOpacity }, { Settings.tintOpacity = $0 }), in: 0.05...MenuBarTint.maxOpacity) { Text("Strength") }
                }
                Toggle("Line under the menu bar", isOn: model.bind({ Settings.showBorder }, { Settings.showBorder = $0 }))
            } header: {
                Text("Menu bar")
            } footer: {
                Text("The tint colors the whole menu bar, its icons and menus included, like a sheet of tinted glass. Clicks go through it.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section {
                Stepper("Spacers: \(Settings.spacerCount)", value: model.bind({ Settings.spacerCount }, { Settings.spacerCount = $0 }), in: 0...5)
                Picker("Space between icons", selection: model.bind({ Settings.itemSpacing }, {
                    Settings.itemSpacing = $0
                    AppBridge.controller?.applySpacing()
                })) {
                    ForEach(ItemSpacing.allCases, id: \.self) { Text($0.title).tag($0) }
                }
            } header: {
                Text("Spacing")
            } footer: {
                Text("Spacers are blank items; ⌘-drag them between icons to group them. Space between icons is a macOS-wide setting that apps pick up when they start, so log out and back in to see it everywhere.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Backup

private struct BackupTab: View {
    @ObservedObject var model: SettingsModel
    @State private var message: String?

    var body: some View {
        Form {
            Section {
                HStack {
                    Button("Export Settings…") { export() }
                    Button("Import Settings…") { importFile() }
                }
                if let message { Text(message).font(.callout).foregroundStyle(.secondary) }
            } header: {
                Text("Backup")
            } footer: {
                Text("Saves every setting, profile, trigger and shortcut to a file, plus where BarManager’s own items sit. Import it on another Mac or after reinstalling.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section {
                Button("Reset All Settings…", role: .destructive) { reset() }
            }
        }
        .formStyle(.grouped)
    }

    private func export() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "BarManager Settings.plist"
        panel.allowedContentTypes = [.propertyList]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try Settings.exportData().write(to: url)
            message = "Saved to \(url.lastPathComponent)."
        } catch {
            message = "Couldn’t save: \(error.localizedDescription)"
        }
    }

    private func importFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.propertyList]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            guard try Settings.importData(Data(contentsOf: url)) else {
                message = "That file isn’t a BarManager settings export."
                return
            }
            model.changed()
            message = "Imported. Where BarManager’s own items sit applies the next time it starts."
        } catch {
            message = "Couldn’t read it: \(error.localizedDescription)"
        }
    }

    private func reset() {
        let alert = NSAlert()
        alert.messageText = "Reset all BarManager settings?"
        alert.informativeText = "Profiles, triggers and shortcuts are deleted too. Export first if you might want them back."
        alert.addButton(withTitle: "Reset")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        Settings.resetAll()
        model.changed()
        message = "Settings reset."
    }
}
