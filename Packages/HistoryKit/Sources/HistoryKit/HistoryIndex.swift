import Foundation

/// Pure ordered index of history entries, newest first. Mutations return a new
/// index plus the entries that fell out, so the store can delete their
/// history-owned files.
public struct HistoryIndex: Codable, Equatable {
    /// Entries newest-first.
    public private(set) var entries: [HistoryEntry]
    /// CleanShot keeps history "about a month" — older entries are pruned.
    public static let maxAge: TimeInterval = 30 * 24 * 60 * 60

    public init(entries: [HistoryEntry] = []) { self.entries = entries }

    /// Insert newest-first, then apply the count cap and the 30-day age prune.
    public func adding(_ entry: HistoryEntry, cap: Int, now: Date = Date())
        -> (index: HistoryIndex, evicted: [HistoryEntry]) {
        var all = entries
        all.insert(entry, at: 0)
        return HistoryIndex(entries: all).pruned(cap: cap, now: now)
    }

    /// Count cap + 30-day prune without adding (run at load).
    public func pruned(cap: Int, now: Date = Date())
        -> (index: HistoryIndex, evicted: [HistoryEntry]) {
        let cutoff = now.addingTimeInterval(-Self.maxAge)
        var kept: [HistoryEntry] = []
        var evicted: [HistoryEntry] = []
        for e in entries {
            if e.date >= cutoff && kept.count < max(cap, 0) { kept.append(e) }
            else { evicted.append(e) }
        }
        return (HistoryIndex(entries: kept), evicted)
    }

    public func removing(id: UUID) -> (index: HistoryIndex, removed: HistoryEntry?) {
        guard let i = entries.firstIndex(where: { $0.id == id }) else { return (self, nil) }
        var all = entries
        let removed = all.remove(at: i)
        return (HistoryIndex(entries: all), removed)
    }

    /// Drops entries whose backing file is gone per the caller's check —
    /// e.g. recordings the user deleted in Finder. Run at load.
    public func prunedOfMissingFiles(exists: (HistoryEntry) -> Bool)
        -> (index: HistoryIndex, removed: [HistoryEntry]) {
        var kept: [HistoryEntry] = []
        var removed: [HistoryEntry] = []
        for e in entries { if exists(e) { kept.append(e) } else { removed.append(e) } }
        return (HistoryIndex(entries: kept), removed)
    }

    // MARK: - JSON

    public func jsonData() throws -> Data {
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try enc.encode(self)
    }

    public init(jsonData: Data) throws {
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        self = try dec.decode(HistoryIndex.self, from: jsonData)
    }
}
