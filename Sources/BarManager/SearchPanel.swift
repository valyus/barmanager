import AppKit
import SwiftUI

/// Ranks names against what the user typed: earlier, tighter matches first.
enum SearchMatcher {
    /// nil = no match. Higher is better.
    static func score(_ query: String, _ name: String) -> Int? {
        let query = query.trimmingCharacters(in: .whitespaces).lowercased()
        let name = name.lowercased()
        guard !query.isEmpty else { return 0 }
        if name.hasPrefix(query) { return 1000 - name.count }
        // A word that starts with the query ("wi" → "Control Center – Wi‑Fi").
        let words = name.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
        if words.contains(where: { $0.hasPrefix(query) }) { return 800 - name.count }
        if let range = name.range(of: query) { return 600 - name.distance(from: name.startIndex, to: range.lowerBound) }
        // Letters in order ("cc" → "Control Center").
        var index = name.startIndex
        var gaps = 0
        for character in query {
            guard let found = name[index...].firstIndex(of: character) else { return nil }
            gaps += name.distance(from: index, to: found)
            index = name.index(after: found)
        }
        return 300 - gaps
    }

    static func filter(_ items: [PicturedEntry], query: String) -> [PicturedEntry] {
        items.compactMap { item in score(query, item.entry.name).map { (item, $0) } }
            .sorted { $0.1 > $1.1 }
            .map(\.0)
    }
}

private final class KeyPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

/// A Spotlight-style box for finding any menu bar icon and opening it.
final class SearchPanel: NSObject, NSWindowDelegate {
    var onChoose: ((MenuBarEntry) -> Void)?

    private var panel: NSPanel?
    private let model = SearchModel()

    var isOpen: Bool { panel != nil }

    func show(_ items: [PicturedEntry]) {
        model.all = items
        model.query = ""
        model.selection = 0
        model.onChoose = { [weak self] entry in
            self?.close()
            self?.onChoose?(entry)
        }
        model.onCancel = { [weak self] in self?.close() }

        if panel == nil {
            let panel = KeyPanel(contentRect: NSRect(x: 0, y: 0, width: 520, height: 360),
                                 styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
                                 backing: .buffered, defer: false)
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = true
            panel.level = .modalPanel
            panel.collectionBehavior = [.canJoinAllSpaces, .transient, .fullScreenAuxiliary]
            panel.isMovableByWindowBackground = true
            panel.delegate = self
            let host = NSHostingView(rootView: SearchView(model: model))
            panel.contentView = host
            self.panel = panel
        }
        guard let panel else { return }
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
        if let visible = screen?.visibleFrame {
            panel.setFrameOrigin(NSPoint(x: visible.midX - panel.frame.width / 2, y: visible.maxY - visible.height * 0.22 - panel.frame.height))
        }
        panel.makeKeyAndOrderFront(nil)
        model.focusToken += 1
    }

    /// Swaps in a fresher list while the panel is open.
    func update(_ items: [PicturedEntry]) {
        model.all = items
    }

    func close() {
        panel?.orderOut(nil)
        panel = nil
    }

    func windowDidResignKey(_ notification: Notification) { close() }
}

final class SearchModel: ObservableObject {
    @Published var all: [PicturedEntry] = []
    @Published var query = "" { didSet { selection = 0 } }
    @Published var selection = 0
    @Published var focusToken = 0
    var onChoose: ((MenuBarEntry) -> Void)?
    var onCancel: (() -> Void)?

    var results: [PicturedEntry] { SearchMatcher.filter(all, query: query) }

    func move(_ delta: Int) {
        let count = results.count
        guard count > 0 else { return }
        selection = (selection + delta + count) % count
    }

    func chooseSelection() {
        let results = self.results
        guard results.indices.contains(selection) else { return }
        onChoose?(results[selection].entry)
    }
}

private struct SearchView: View {
    @ObservedObject var model: SearchModel
    @FocusState private var focused: Bool

    var body: some View {
        let results = model.results
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").font(.title2).foregroundStyle(.secondary)
                TextField("Search menu bar icons", text: $model.query)
                    .textFieldStyle(.plain)
                    .font(.title2)
                    .focused($focused)
                    .onSubmit { model.chooseSelection() }
                    .onKeyPress(.downArrow) { model.move(1); return .handled }
                    .onKeyPress(.upArrow) { model.move(-1); return .handled }
                    .onKeyPress(.escape) { model.onCancel?(); return .handled }
            }
            .padding(14)
            Divider()
            if results.isEmpty {
                Text(model.all.isEmpty ? "Finding icons…" : "No icons match")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 2) {
                            ForEach(Array(results.enumerated()), id: \.offset) { index, item in
                                row(item, selected: index == model.selection)
                                    .id(index)
                                    .contentShape(Rectangle())
                                    .onTapGesture { model.onChoose?(item.entry) }
                            }
                        }
                        .padding(6)
                    }
                    .onChange(of: model.selection) { _, selection in proxy.scrollTo(selection) }
                }
            }
        }
        .frame(width: 520, height: 360)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        .onExitCommand { model.onCancel?() }
        .onAppear { focused = true }
        .onChange(of: model.focusToken) { _, _ in focused = true }
    }

    private func row(_ item: PicturedEntry, selected: Bool) -> some View {
        HStack(spacing: 10) {
            Group {
                if let image = item.image {
                    Image(nsImage: image).resizable().aspectRatio(contentMode: .fit)
                } else {
                    Image(systemName: "questionmark.square.dashed")
                }
            }
            .frame(width: 34, height: 18)
            Text(item.entry.name).lineLimit(1)
            Spacer()
            Text(item.section.title)
                .font(.caption)
                .foregroundStyle(selected ? Color.white.opacity(0.85) : .secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .foregroundStyle(selected ? Color.white : Color.primary)
        .background(selected ? Color.accentColor : Color.clear, in: RoundedRectangle(cornerRadius: 7))
    }
}
