import Foundation

/// File-backed history: a JSON index plus history-owned image/thumbnail files
/// in one directory. Not thread-safe — the app calls it from the main actor
/// only. IO failures log via NSLog and degrade: a failed write never blocks
/// the capture flow.
public final class HistoryStore {
    public let directory: URL
    public private(set) var index: HistoryIndex

    private var indexURL: URL { directory.appendingPathComponent("history.json") }

    /// Loads (or starts) the index, then applies retention: count cap, 30-day
    /// age prune, and missing-backing-file prune. Evicted entries' history-
    /// owned files are deleted. Corrupt index → start empty (logged).
    public init(directory: URL, cap: Int, now: Date = Date()) {
        self.directory = directory
        try? FileManager.default.createDirectory(at: directory,
                                                 withIntermediateDirectories: true)
        var loaded = HistoryIndex()
        if let data = try? Data(contentsOf: directory.appendingPathComponent("history.json")) {
            do { loaded = try HistoryIndex(jsonData: data) }
            catch { NSLog("History: corrupt index, starting empty: \(error)") }
        }
        let (aged, evicted) = loaded.pruned(cap: cap, now: now)
        let (alive, missing) = aged.prunedOfMissingFiles { entry in
            switch entry.kind {
            case .screenshot:
                guard let f = entry.imageFile else { return false }
                return FileManager.default.fileExists(
                    atPath: directory.appendingPathComponent(f).path)
            case .recording:
                guard let p = entry.filePath else { return false }
                return FileManager.default.fileExists(atPath: p)
            }
        }
        self.index = alive
        deleteOwnedFiles(of: evicted + missing)
        saveIndex()
    }

    // MARK: - Adding

    /// Stores a history-owned full-res PNG copy + thumbnail. Returns nil (and
    /// logs) when any write fails — the capture flow is never blocked.
    @discardableResult
    public func addScreenshot(pngData: Data, cap: Int, date: Date = Date()) -> HistoryEntry? {
        guard let thumb = ThumbnailRenderer.jpegThumbnail(from: pngData) else {
            NSLog("History: thumbnail failed, skipping entry"); return nil
        }
        let id = UUID()
        let imageName = "\(id.uuidString).png"
        let thumbName = "\(id.uuidString)-thumb.jpg"
        do {
            try pngData.write(to: directory.appendingPathComponent(imageName), options: .atomic)
            try thumb.write(to: directory.appendingPathComponent(thumbName), options: .atomic)
        } catch {
            NSLog("History: couldn't write files: \(error)")
            // The PNG may have landed before the thumb write failed — don't
            // leave a multi-MB orphan behind.
            try? FileManager.default.removeItem(at: directory.appendingPathComponent(imageName))
            return nil
        }
        let entry = HistoryEntry(id: id, kind: .screenshot, date: date,
                                 imageFile: imageName, thumbFile: thumbName)
        insert(entry, cap: cap, now: date)
        return entry
    }

    /// Stores a reference to the user's saved recording plus a thumbnail —
    /// the video itself is never duplicated.
    @discardableResult
    public func addRecording(filePath: String, thumbnailSource: Data, cap: Int,
                             date: Date = Date()) -> HistoryEntry? {
        guard let thumb = ThumbnailRenderer.jpegThumbnail(from: thumbnailSource) else {
            NSLog("History: thumbnail failed, skipping entry"); return nil
        }
        let id = UUID()
        let thumbName = "\(id.uuidString)-thumb.jpg"
        do {
            try thumb.write(to: directory.appendingPathComponent(thumbName), options: .atomic)
        } catch {
            NSLog("History: couldn't write thumbnail: \(error)")
            return nil
        }
        let entry = HistoryEntry(id: id, kind: .recording, date: date,
                                 filePath: filePath, thumbFile: thumbName)
        insert(entry, cap: cap, now: date)
        return entry
    }

    private func insert(_ entry: HistoryEntry, cap: Int, now: Date) {
        let (next, evicted) = index.adding(entry, cap: cap, now: now)
        index = next
        deleteOwnedFiles(of: evicted)
        saveIndex()
    }

    // MARK: - Lookup

    public func entry(id: UUID) -> HistoryEntry? {
        index.entries.first { $0.id == id }
    }

    public func thumbURL(for entry: HistoryEntry) -> URL {
        directory.appendingPathComponent(entry.thumbFile)
    }

    public func imageURL(for entry: HistoryEntry) -> URL? {
        entry.imageFile.map { directory.appendingPathComponent($0) }
    }

    public func savedFileURL(for entry: HistoryEntry) -> URL? {
        entry.filePath.map { URL(fileURLWithPath: $0) }
    }

    /// False for recordings whose saved file the user deleted ("file missing").
    public func savedFileExists(_ entry: HistoryEntry) -> Bool {
        guard let p = entry.filePath else { return true }
        return FileManager.default.fileExists(atPath: p)
    }

    // MARK: - Removal

    /// Removes the entry and its history-owned files. Never touches a
    /// recording's saved file.
    public func remove(id: UUID) {
        let (next, removed) = index.removing(id: id)
        index = next
        if let removed { deleteOwnedFiles(of: [removed]) }
        saveIndex()
    }

    /// Deletes every entry and all history-owned files.
    public func clearAll() {
        deleteOwnedFiles(of: index.entries)
        index = HistoryIndex()
        saveIndex()
    }

    // MARK: - Files

    private func deleteOwnedFiles(of entries: [HistoryEntry]) {
        for e in entries {
            if let f = e.imageFile {
                try? FileManager.default.removeItem(at: directory.appendingPathComponent(f))
            }
            try? FileManager.default.removeItem(at: directory.appendingPathComponent(e.thumbFile))
        }
    }

    private func saveIndex() {
        do { try index.jsonData().write(to: indexURL, options: .atomic) }
        catch { NSLog("History: couldn't write index: \(error)") }
    }
}
