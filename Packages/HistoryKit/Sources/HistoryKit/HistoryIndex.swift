import Foundation

/// Pure ordered index of history entries, newest first. Mutations return a new
/// index plus the entries that fell out, so the store can delete their
/// history-owned files.
public struct HistoryIndex: Codable, Equatable {
    /// Entries newest-first.
    public private(set) var entries: [HistoryEntry]

    public init(entries: [HistoryEntry] = []) { self.entries = entries }

    /// Insert newest-first, then apply the count cap and the age prune.
    /// `maxAge` is the cache-retention window; nil keeps entries forever.
    public func adding(_ entry: HistoryEntry, cap: Int, maxAge: TimeInterval?,
                       now: Date = Date())
        -> (index: HistoryIndex, evicted: [HistoryEntry]) {
        var all = entries
        all.insert(entry, at: 0)
        return HistoryIndex(entries: all).pruned(cap: cap, maxAge: maxAge, now: now)
    }

    /// Count cap + age prune without adding (run at load and on the sweep timer).
    /// `maxAge` is the cache-retention window; nil keeps entries forever.
    public func pruned(cap: Int, maxAge: TimeInterval?, now: Date = Date())
        -> (index: HistoryIndex, evicted: [HistoryEntry]) {
        let cutoff = maxAge.map { now.addingTimeInterval(-$0) }
        var kept: [HistoryEntry] = []
        var evicted: [HistoryEntry] = []
        for e in entries {
            let fresh = cutoff.map { e.date >= $0 } ?? true
            if fresh && kept.count < max(cap, 0) { kept.append(e) }
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
