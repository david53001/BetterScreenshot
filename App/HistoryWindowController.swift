import AppKit
import SwiftUI
import HistoryKit

/// Closures the History window needs from the capture layer (annotate/pin
/// reuse CaptureCoordinator's existing flows).
struct HistoryWindowActions {
    var annotate: (CGImage) -> Void
    var pin: (CGImage) -> Void
}

/// Owns the single History window — a normal titled window like Settings,
/// hosted via NSHostingController (the SettingsWindowController pattern).
@MainActor
final class HistoryWindowController {
    private var window: NSWindow?
    private let history: HistoryService
    private let actions: HistoryWindowActions

    init(history: HistoryService, actions: HistoryWindowActions) {
        self.history = history
        self.actions = actions
    }

    func show() {
        if window == nil {
            let view = HistoryView(history: history, actions: actions)
            let w = NSWindow(contentViewController: NSHostingController(rootView: view))
            w.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            w.title = "History"
            w.setContentSize(NSSize(width: 700, height: 500))
            w.isReleasedWhenClosed = false
            w.center()
            window = w
        }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)   // ★ after makeKey, matching SettingsWindowController
    }
}

struct HistoryView: View {
    @ObservedObject var history: HistoryService
    let actions: HistoryWindowActions
    @State private var selection: UUID?

    private let columns = [GridItem(.adaptive(minimum: 180, maximum: 260), spacing: 12)]

    var body: some View {
        Group {
            if history.entries.isEmpty {
                Text("No captures yet")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(history.entries) { entry in
                            HistoryCell(entry: entry, history: history,
                                        isSelected: selection == entry.id)
                                .gesture(TapGesture(count: 2).onEnded { open(entry) })
                                .onTapGesture { selection = entry.id }
                                .contextMenu { contextItems(for: entry) }
                        }
                    }
                    .padding(12)
                }
            }
        }
        .safeAreaInset(edge: .bottom) { actionBar }
        .frame(minWidth: 520, minHeight: 360)
    }

    private var selected: HistoryEntry? { history.entries.first { $0.id == selection } }

    private var actionBar: some View {
        HStack(spacing: 8) {
            Text("\(history.entries.count) item\(history.entries.count == 1 ? "" : "s")")
                .font(.caption).foregroundStyle(.secondary)
            Spacer()
            Button("Copy") { if let e = selected { copy(e) } }
                .disabled(selected == nil)
            Button("Annotate") { if let e = selected { annotate(e) } }
                .disabled(selected?.kind != .screenshot)
            Button("Pin") { if let e = selected { pin(e) } }
                .disabled(selected?.kind != .screenshot)
            Button("Show in Finder") { if let e = selected { history.revealInFinder(e) } }
                .disabled(selected.map { !history.canReveal($0) } ?? true)
            Button("Delete") { if let e = selected { delete(e) } }
                .disabled(selected == nil)
        }
        .padding(10)
        .background(.bar)
    }

    @ViewBuilder
    private func contextItems(for entry: HistoryEntry) -> some View {
        Button("Copy") { copy(entry) }
        if entry.kind == .screenshot {
            Button("Annotate") { annotate(entry) }
            Button("Pin") { pin(entry) }
        }
        if history.canReveal(entry) {
            Button("Show in Finder") { history.revealInFinder(entry) }
        }
        Divider()
        Button("Delete", role: .destructive) { delete(entry) }
    }

    /// Double-click: screenshots → editor, recordings → default player.
    private func open(_ entry: HistoryEntry) {
        switch entry.kind {
        case .screenshot: annotate(entry)
        case .recording:
            if let url = history.savedFileURL(for: entry) { NSWorkspace.shared.open(url) }
        }
    }

    private func copy(_ entry: HistoryEntry) { history.copyToClipboard(entry) }

    private func annotate(_ entry: HistoryEntry) {
        guard let image = history.image(for: entry) else { return }
        actions.annotate(image)
    }

    private func pin(_ entry: HistoryEntry) {
        guard let image = history.image(for: entry) else { return }
        actions.pin(image)
    }

    private func delete(_ entry: HistoryEntry) {
        if selection == entry.id { selection = nil }
        history.delete(entry)
    }
}

private struct HistoryCell: View {
    let entry: HistoryEntry
    let history: HistoryService
    let isSelected: Bool

    private static let relative: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f
    }()

    var body: some View {
        VStack(spacing: 6) {
            Group {
                if let thumb = history.thumbnail(for: entry) {
                    Image(nsImage: thumb).resizable().scaledToFit()
                } else {
                    Image(systemName: "photo")
                        .font(.largeTitle).foregroundStyle(.tertiary)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 110)
            .background(Color.gray.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            HStack(spacing: 4) {
                Image(systemName: entry.kind == .recording ? "film" : "camera")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(Self.relative.localizedString(for: entry.date, relativeTo: Date()))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if entry.kind == .recording && !history.savedFileExists(entry) {
                    Label("file missing", systemImage: "exclamationmark.triangle")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
                Spacer(minLength: 0)
            }
        }
        .padding(6)
        .background(RoundedRectangle(cornerRadius: 8)
            .fill(isSelected ? Color.accentColor.opacity(0.15) : Color.clear))
        .overlay(RoundedRectangle(cornerRadius: 8)
            .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2))
        .contentShape(Rectangle())
    }
}
