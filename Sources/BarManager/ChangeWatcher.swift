import AppKit
import ScreenCaptureKit

/// Takes a small snapshot of each hidden menu bar item every couple of seconds
/// and reports items whose picture changed (a new badge, a different state…).
/// Needs Screen Recording permission. Main thread only.
final class ChangeWatcher {
    /// Window IDs to watch right now; return [] to skip a round.
    var itemsToWatch: (() -> [CGWindowID])?
    /// Called with the items that changed since the previous round.
    var onChange: (([CGWindowID]) -> Void)?

    /// Latest snapshot of each watched item, for showing in menus.
    private(set) var snapshots: [CGWindowID: NSImage] = [:]
    /// When each item last changed, until the user looks at it.
    private(set) var lastChanged: [CGWindowID: Date] = [:]

    /// The user has seen this item, so it no longer counts as changed.
    func markSeen(_ id: CGWindowID) { lastChanged[id] = nil }

    private var timer: Timer?
    private var fingerprints: [CGWindowID: Fingerprint] = [:]
    private var busy = false
    private var generation = 0

    static var hasPermission: Bool { CGPreflightScreenCaptureAccess() }

    /// Shows the system prompt (or opens System Settings) the first time.
    static func requestPermission() { CGRequestScreenCaptureAccess() }

    func start() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in self?.tick() }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        rebaseline()
    }

    /// Forget what items looked like, so the next round sets a new baseline.
    func rebaseline() {
        fingerprints = [:]
        generation += 1
    }

    private func tick() {
        guard !busy, Self.hasPermission, let ids = itemsToWatch?(), !ids.isEmpty else { return }
        busy = true
        let generation = self.generation
        Task { @MainActor [weak self] in
            let captured = await Self.capture(ids)
            guard let self else { return }
            self.busy = false
            guard generation == self.generation else { return } // rebaselined meanwhile

            var changed: [CGWindowID] = []
            for (id, image) in captured {
                let print = Fingerprint(image)
                if let old = self.fingerprints[id], old.differs(from: print) { changed.append(id) }
                self.fingerprints[id] = print
                self.snapshots[id] = NSImage(cgImage: image, size: NSSize(width: image.width / 2, height: image.height / 2))
            }
            let watched = Set(ids)
            self.fingerprints = self.fingerprints.filter { watched.contains($0.key) }
            self.snapshots = self.snapshots.filter { watched.contains($0.key) }
            self.lastChanged = self.lastChanged.filter { watched.contains($0.key) }

            // Most icons changing at once means the menu bar's look changed
            // (dark mode, wallpaper tint), not that something needs attention.
            guard !changed.isEmpty, changed.count == 1 || changed.count * 2 < captured.count else { return }
            let now = Date()
            for id in changed { self.lastChanged[id] = now }
            self.onChange?(changed)
        }
    }

    private static func capture(_ ids: [CGWindowID]) async -> [(CGWindowID, CGImage)] {
        guard let content = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false) else { return [] }
        let windows = Dictionary(content.windows.map { ($0.windowID, $0) }, uniquingKeysWith: { a, _ in a })
        var result: [(CGWindowID, CGImage)] = []
        for id in ids {
            guard let window = windows[id] else { continue }
            let config = SCStreamConfiguration()
            config.width = max(Int(window.frame.width * 2), 1)
            config.height = max(Int(window.frame.height * 2), 1)
            config.showsCursor = false
            let filter = SCContentFilter(desktopIndependentWindow: window)
            if let image = try? await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config) {
                result.append((id, image))
            }
        }
        return result
    }
}

/// A tiny downscaled copy of an item's picture, compared with some tolerance so
/// rendering noise doesn't count as a change.
private struct Fingerprint {
    static let width = 48, height = 24

    let size: CGSize
    let pixels: [UInt8]

    init(_ image: CGImage) {
        size = CGSize(width: image.width, height: image.height)
        var pixels = [UInt8](repeating: 0, count: Self.width * Self.height * 4)
        pixels.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(
                data: buffer.baseAddress, width: Self.width, height: Self.height, bitsPerComponent: 8,
                bytesPerRow: Self.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return }
            context.interpolationQuality = .medium
            context.draw(image, in: CGRect(x: 0, y: 0, width: Self.width, height: Self.height))
        }
        self.pixels = pixels
    }

    func differs(from other: Fingerprint) -> Bool {
        if abs(size.width - other.size.width) > 2 { return true } // got wider or narrower
        var changedPixels = 0
        for i in stride(from: 0, to: pixels.count, by: 4) {
            let delta = (0..<4).map { abs(Int(pixels[i + $0]) - Int(other.pixels[i + $0])) }.max() ?? 0
            if delta > 40 { changedPixels += 1 }
        }
        return changedPixels > 4
    }
}
