import TestKit
import Foundation
@testable import HistoryKit

/// Fixed whole-second "now" so JSON round-trips compare equal under ISO-8601.
private let now = Date(timeIntervalSince1970: 1_900_000_000)

private func entry(_ kind: HistoryKind = .screenshot, daysAgo: Double = 0) -> HistoryEntry {
    HistoryEntry(kind: kind, date: now.addingTimeInterval(-daysAgo * 86_400),
                 imageFile: kind == .screenshot ? "img.png" : nil,
                 filePath: kind == .recording ? "/tmp/rec.mp4" : nil,
                 thumbFile: "thumb.jpg")
}

let historyIndexTests: [TestCase] = [
    TestCase("addingInsertsNewestFirst") { t in
        let a = entry(daysAgo: 1), b = entry()
        var idx = HistoryIndex()
        idx = idx.adding(a, cap: 50, now: now).index
        let (idx2, evicted) = idx.adding(b, cap: 50, now: now)
        t.equal(idx2.entries.map(\.id), [b.id, a.id])
        t.isTrue(evicted.isEmpty)
    },
    TestCase("countCapEvictsOldest") { t in
        let a = entry(daysAgo: 2), b = entry(daysAgo: 1), c = entry()
        var idx = HistoryIndex()
        idx = idx.adding(a, cap: 2, now: now).index
        idx = idx.adding(b, cap: 2, now: now).index
        let (idx2, evicted) = idx.adding(c, cap: 2, now: now)
        t.equal(idx2.entries.map(\.id), [c.id, b.id])
        t.equal(evicted.map(\.id), [a.id])
    },
    TestCase("entriesOlderThan30DaysArePruned") { t in
        let old = entry(daysAgo: 31), fresh = entry()
        let idx = HistoryIndex(entries: [fresh, old])
        let (pruned, evicted) = idx.adding(entry(daysAgo: 0.5), cap: 50, now: now)
        t.equal(pruned.entries.count, 2)
        t.equal(evicted.map(\.id), [old.id])
    },
    TestCase("exactly30DayOldEntrySurvives") { t in
        let edge = entry(daysAgo: 30)
        let (idx, evicted) = HistoryIndex(entries: [edge]).pruned(cap: 50, now: now)
        t.equal(idx.entries.map(\.id), [edge.id])
        t.isTrue(evicted.isEmpty)
    },
    TestCase("prunedAppliesCapAndAgeAtLoad") { t in
        let a = entry(), b = entry(daysAgo: 1), old = entry(daysAgo: 40)
        let (idx, evicted) = HistoryIndex(entries: [a, b, old]).pruned(cap: 1, now: now)
        t.equal(idx.entries.map(\.id), [a.id])
        t.equal(Set(evicted.map(\.id)), Set([b.id, old.id]))
    },
    TestCase("removingReturnsEntry") { t in
        let a = entry(), b = entry(daysAgo: 1)
        let (idx, removed) = HistoryIndex(entries: [a, b]).removing(id: b.id)
        t.equal(idx.entries.map(\.id), [a.id])
        t.equal(removed?.id, b.id)
    },
    TestCase("removingUnknownIDIsNoOp") { t in
        let a = entry()
        let (idx, removed) = HistoryIndex(entries: [a]).removing(id: UUID())
        t.equal(idx.entries.map(\.id), [a.id])
        t.isNil(removed)
    },
    TestCase("prunedOfMissingFilesDropsOnlyMissing") { t in
        let alive = entry(.recording), dead = entry(.recording, daysAgo: 1)
        let (idx, removed) = HistoryIndex(entries: [alive, dead])
            .prunedOfMissingFiles { $0.id == alive.id }
        t.equal(idx.entries.map(\.id), [alive.id])
        t.equal(removed.map(\.id), [dead.id])
    },
    TestCase("jsonRoundTrip") { t in
        let idx = HistoryIndex(entries: [entry(), entry(.recording, daysAgo: 1)])
        guard let data = t.unwrap(try? idx.jsonData()) else { return }
        guard let back = t.unwrap(try? HistoryIndex(jsonData: data)) else { return }
        t.equal(back, idx)
    },
    TestCase("corruptJSONThrows") { t in
        t.isNil(try? HistoryIndex(jsonData: Data("not json".utf8)))
    },
]
