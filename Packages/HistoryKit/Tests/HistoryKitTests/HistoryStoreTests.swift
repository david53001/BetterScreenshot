import TestKit
import Foundation
@testable import HistoryKit

private func makeTempDir() -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("HistoryStoreTests-\(UUID().uuidString)", isDirectory: true)
}

let historyStoreTests: [TestCase] = [
    TestCase("addScreenshotWritesCopyThumbAndIndex") { t in
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = HistoryStore(directory: dir, cap: 50, maxAge: 30 * 24 * 60 * 60)
        guard let entry = t.unwrap(store.addScreenshot(pngData: makePNGData(), cap: 50, maxAge: 30 * 24 * 60 * 60)) else { return }
        t.equal(entry.kind, .screenshot)
        t.notNil(entry.imageFile)
        t.isNil(entry.filePath)
        t.isTrue(FileManager.default.fileExists(atPath: store.thumbURL(for: entry).path))
        guard let imageURL = t.unwrap(store.imageURL(for: entry)) else { return }
        t.isTrue(FileManager.default.fileExists(atPath: imageURL.path))
        t.isTrue(FileManager.default.fileExists(
            atPath: dir.appendingPathComponent("history.json").path))
        t.equal(store.index.entries.count, 1)
    },
    TestCase("addRecordingStoresReferenceNotCopy") { t in
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let saved = FileManager.default.temporaryDirectory
            .appendingPathComponent("rec-\(UUID().uuidString).mp4")
        FileManager.default.createFile(atPath: saved.path, contents: Data([0x0]))
        defer { try? FileManager.default.removeItem(at: saved) }
        let store = HistoryStore(directory: dir, cap: 50, maxAge: 30 * 24 * 60 * 60)
        guard let entry = t.unwrap(store.addRecording(
            filePath: saved.path, thumbnailSource: makePNGData(), cap: 50, maxAge: 30 * 24 * 60 * 60)) else { return }
        t.equal(entry.kind, .recording)
        t.isNil(entry.imageFile)
        t.equal(entry.filePath, saved.path)
        t.isTrue(FileManager.default.fileExists(atPath: store.thumbURL(for: entry).path))
    },
    TestCase("reloadRoundTripsIndex") { t in
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = HistoryStore(directory: dir, cap: 50, maxAge: 30 * 24 * 60 * 60)
        store.addScreenshot(pngData: makePNGData(), cap: 50, maxAge: 30 * 24 * 60 * 60)
        store.addScreenshot(pngData: makePNGData(), cap: 50, maxAge: 30 * 24 * 60 * 60)
        let reloaded = HistoryStore(directory: dir, cap: 50, maxAge: 30 * 24 * 60 * 60)
        t.equal(reloaded.index.entries.map(\.id), store.index.entries.map(\.id))
    },
    TestCase("capEvictionDeletesOwnedFiles") { t in
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = HistoryStore(directory: dir, cap: 1, maxAge: 30 * 24 * 60 * 60)
        guard let first = t.unwrap(store.addScreenshot(pngData: makePNGData(), cap: 1, maxAge: 30 * 24 * 60 * 60)) else { return }
        let firstImage = store.imageURL(for: first)!
        let firstThumb = store.thumbURL(for: first)
        store.addScreenshot(pngData: makePNGData(), cap: 1, maxAge: 30 * 24 * 60 * 60)
        t.equal(store.index.entries.count, 1)
        t.isFalse(FileManager.default.fileExists(atPath: firstImage.path))
        t.isFalse(FileManager.default.fileExists(atPath: firstThumb.path))
    },
    TestCase("removeNeverDeletesSavedRecordingFile") { t in
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let saved = FileManager.default.temporaryDirectory
            .appendingPathComponent("rec-\(UUID().uuidString).mp4")
        FileManager.default.createFile(atPath: saved.path, contents: Data([0x0]))
        defer { try? FileManager.default.removeItem(at: saved) }
        let store = HistoryStore(directory: dir, cap: 50, maxAge: 30 * 24 * 60 * 60)
        guard let entry = t.unwrap(store.addRecording(
            filePath: saved.path, thumbnailSource: makePNGData(), cap: 50, maxAge: 30 * 24 * 60 * 60)) else { return }
        let thumb = store.thumbURL(for: entry)
        store.remove(id: entry.id)
        t.isTrue(store.index.entries.isEmpty)
        t.isFalse(FileManager.default.fileExists(atPath: thumb.path))
        t.isTrue(FileManager.default.fileExists(atPath: saved.path),
                 "user's saved recording must survive history delete")
    },
    TestCase("clearAllEmptiesIndexAndDeletesOwnedFiles") { t in
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = HistoryStore(directory: dir, cap: 50, maxAge: 30 * 24 * 60 * 60)
        guard let e = t.unwrap(store.addScreenshot(pngData: makePNGData(), cap: 50, maxAge: 30 * 24 * 60 * 60)) else { return }
        let image = store.imageURL(for: e)!
        store.clearAll()
        t.isTrue(store.index.entries.isEmpty)
        t.isFalse(FileManager.default.fileExists(atPath: image.path))
        let reloaded = HistoryStore(directory: dir, cap: 50, maxAge: 30 * 24 * 60 * 60)
        t.isTrue(reloaded.index.entries.isEmpty)
    },
    TestCase("corruptIndexStartsEmpty") { t in
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? Data("garbage".utf8).write(to: dir.appendingPathComponent("history.json"))
        let store = HistoryStore(directory: dir, cap: 50, maxAge: 30 * 24 * 60 * 60)
        t.isTrue(store.index.entries.isEmpty)
    },
    TestCase("missingRecordingFilePrunedAtLoad") { t in
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let saved = FileManager.default.temporaryDirectory
            .appendingPathComponent("rec-\(UUID().uuidString).mp4")
        FileManager.default.createFile(atPath: saved.path, contents: Data([0x0]))
        let store = HistoryStore(directory: dir, cap: 50, maxAge: 30 * 24 * 60 * 60)
        store.addRecording(filePath: saved.path, thumbnailSource: makePNGData(), cap: 50, maxAge: 30 * 24 * 60 * 60)
        try? FileManager.default.removeItem(at: saved)   // user deletes it in Finder
        let reloaded = HistoryStore(directory: dir, cap: 50, maxAge: 30 * 24 * 60 * 60)
        t.isTrue(reloaded.index.entries.isEmpty)
    },
    TestCase("agePruneAppliesAtLoad") { t in
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = HistoryStore(directory: dir, cap: 50, maxAge: 30 * 24 * 60 * 60)
        store.addScreenshot(pngData: makePNGData(), cap: 50, maxAge: 30 * 24 * 60 * 60,
                            date: Date().addingTimeInterval(-31 * 86_400))
        t.equal(store.index.entries.count, 1)
        let reloaded = HistoryStore(directory: dir, cap: 50, maxAge: 30 * 24 * 60 * 60)
        t.isTrue(reloaded.index.entries.isEmpty)
    },
    TestCase("neverRetentionKeepsOldEntriesAtLoad") { t in
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = HistoryStore(directory: dir, cap: 50, maxAge: nil)
        store.addScreenshot(pngData: makePNGData(), cap: 50, maxAge: nil,
                            date: Date().addingTimeInterval(-365 * 86_400))
        let reloaded = HistoryStore(directory: dir, cap: 50, maxAge: nil)
        t.equal(reloaded.index.entries.count, 1)
    },
    TestCase("pruneExpiredDropsEntriesPastRetentionAndDeletesCachedFiles") { t in
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        // Seed with retention off, so the second add can't evict the first at
        // insert time — this test is about the sweep, not the on-add prune.
        let store = HistoryStore(directory: dir, cap: 50, maxAge: nil)
        let now = Date()
        guard let old = t.unwrap(store.addScreenshot(pngData: makePNGData(), cap: 50,
                                                     maxAge: nil,
                                                     date: now.addingTimeInterval(-1801))),
              let fresh = t.unwrap(store.addScreenshot(pngData: makePNGData(), cap: 50,
                                                       maxAge: nil, date: now))
        else { return }
        let oldImage = dir.appendingPathComponent(old.imageFile ?? "")
        t.isTrue(FileManager.default.fileExists(atPath: oldImage.path))

        t.isTrue(store.pruneExpired(cap: 50, maxAge: 1800, now: now))
        t.equal(store.index.entries.map(\.id), [fresh.id])
        // the expired capture's cached copy + thumbnail are gone from disk
        t.isFalse(FileManager.default.fileExists(atPath: oldImage.path))
        t.isFalse(FileManager.default.fileExists(
            atPath: dir.appendingPathComponent(old.thumbFile).path))
        // nothing left to evict -> no republish
        t.isFalse(store.pruneExpired(cap: 50, maxAge: 1800, now: now))
    },
    TestCase("pruneExpiredNeverTouchesARecordingsSavedFile") { t in
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let saved = FileManager.default.temporaryDirectory
            .appendingPathComponent("rec-\(UUID().uuidString).mp4")
        FileManager.default.createFile(atPath: saved.path, contents: Data([0x0]))
        defer { try? FileManager.default.removeItem(at: saved) }
        let store = HistoryStore(directory: dir, cap: 50, maxAge: 1800)
        let now = Date()
        store.addRecording(filePath: saved.path, thumbnailSource: makePNGData(), cap: 50,
                           maxAge: 1800, date: now.addingTimeInterval(-1801))
        t.isTrue(store.pruneExpired(cap: 50, maxAge: 1800, now: now))
        t.isTrue(store.index.entries.isEmpty)
        t.isTrue(FileManager.default.fileExists(atPath: saved.path))
    },
    TestCase("savedFileExistsReflectsDisk") { t in
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let saved = FileManager.default.temporaryDirectory
            .appendingPathComponent("rec-\(UUID().uuidString).mp4")
        FileManager.default.createFile(atPath: saved.path, contents: Data([0x0]))
        let store = HistoryStore(directory: dir, cap: 50, maxAge: 30 * 24 * 60 * 60)
        guard let entry = t.unwrap(store.addRecording(
            filePath: saved.path, thumbnailSource: makePNGData(), cap: 50, maxAge: 30 * 24 * 60 * 60)) else { return }
        t.isTrue(store.savedFileExists(entry))
        try? FileManager.default.removeItem(at: saved)
        t.isFalse(store.savedFileExists(entry))
    },
]
