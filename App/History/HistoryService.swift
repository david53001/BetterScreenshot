import AppKit
import ImageIO
import CaptureKit
import HistoryKit
import OverlayKit

/// App-side façade over HistoryKit: owns the store and the restore LIFO,
/// applies the settings toggle/cap, and publishes entries for the History
/// window. PNG encoding reuses CaptureKit's ImageEncoder so HistoryKit stays
/// dependency-free.
@MainActor
final class HistoryService: ObservableObject {
    @Published private(set) var entries: [HistoryEntry] = []

    private let store: HistoryStore
    private var restoreStack = RestoreStack()
    private let settings: SettingsStore
    private let hud = HUDController()

    init(settings: SettingsStore) {
        self.settings = settings
        let base = FileManager.default.urls(for: .applicationSupportDirectory,
                                            in: .userDomainMask).first!
            .appendingPathComponent("BetterScreenshot/History", isDirectory: true)
        self.store = HistoryStore(directory: base, cap: settings.settings.historyCap)
        self.entries = store.index.entries
    }

    // MARK: - Recording captures (silent bookkeeping; never blocks the flow)

    /// Adds a screenshot (every after-capture mode, including copy-only).
    /// Returns the entry id for restore tracking, or nil when history is off
    /// or the write failed.
    @discardableResult
    func recordScreenshot(_ image: CGImage) -> UUID? {
        guard settings.settings.historyEnabled else { return nil }
        guard let png = ImageEncoder.encode(image, as: .png) else { return nil }
        let entry = store.addScreenshot(pngData: png, cap: settings.settings.historyCap)
        entries = store.index.entries
        return entry?.id
    }

    /// Adds a finished recording (reference + thumbnail, no video copy).
    @discardableResult
    func recordRecording(fileURL: URL, thumbnailSource: NSImage) -> UUID? {
        guard settings.settings.historyEnabled else { return nil }
        guard let tiff = thumbnailSource.tiffRepresentation else { return nil }
        let entry = store.addRecording(filePath: fileURL.path, thumbnailSource: tiff,
                                       cap: settings.settings.historyCap)
        entries = store.index.entries
        return entry?.id
    }

    // MARK: - Restore Recently Closed

    /// Track a ✕-closed or evicted overlay for restore.
    func noteOverlayClosed(historyID: UUID?) {
        guard let historyID else { return }
        restoreStack.push(historyID)
    }

    var canRestore: Bool { !restoreStack.isEmpty }

    /// Pops the newest restorable entry still present in history.
    func popRestorable() -> HistoryEntry? {
        while let id = restoreStack.pop() {
            if let entry = store.entry(id: id) { return entry }
        }
        return nil
    }

    // MARK: - History window actions

    func delete(_ entry: HistoryEntry) {
        store.remove(id: entry.id)
        entries = store.index.entries
    }

    func clearAll() {
        store.clearAll()
        entries = store.index.entries
    }

    func thumbnail(for entry: HistoryEntry) -> NSImage? {
        NSImage(contentsOf: store.thumbURL(for: entry))
    }

    /// Full-resolution stored screenshot (nil for recordings).
    func image(for entry: HistoryEntry) -> CGImage? {
        guard let url = store.imageURL(for: entry),
              let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(src, 0, nil)
    }

    func savedFileURL(for entry: HistoryEntry) -> URL? { store.savedFileURL(for: entry) }
    func savedFileExists(_ entry: HistoryEntry) -> Bool { store.savedFileExists(entry) }

    /// Copy: image for screenshots, file URL for recordings. HUD confirms.
    func copyToClipboard(_ entry: HistoryEntry) {
        switch entry.kind {
        case .screenshot:
            guard let cg = image(for: entry) else { return }
            let rep = NSBitmapImageRep(cgImage: cg)
            let img = NSImage(); img.addRepresentation(rep)
            NSPasteboard.general.clearContents()
            // Image data first, plus the persistent stored PNG's file URL so
            // pasting into a terminal/Claude Code inserts a usable path.
            var objects: [NSPasteboardWriting] = [img]
            if let url = store.imageURL(for: entry) { objects.append(url as NSURL) }
            NSPasteboard.general.writeObjects(objects)
            hud.show("Copied")
        case .recording:
            guard let url = savedFileURL(for: entry) else { return }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.writeObjects([url as NSURL])
            hud.show("File copied")
        }
    }

    /// Show in Finder targets the saved recording file, or the history-owned
    /// screenshot copy.
    func canReveal(_ entry: HistoryEntry) -> Bool {
        guard let url = revealURL(for: entry) else { return false }
        return FileManager.default.fileExists(atPath: url.path)
    }

    func revealInFinder(_ entry: HistoryEntry) {
        guard let url = revealURL(for: entry),
              FileManager.default.fileExists(atPath: url.path) else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    private func revealURL(for entry: HistoryEntry) -> URL? {
        store.savedFileURL(for: entry) ?? store.imageURL(for: entry)
    }
}
