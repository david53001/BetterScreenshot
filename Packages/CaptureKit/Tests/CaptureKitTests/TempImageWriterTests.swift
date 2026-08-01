import TestKit
import CoreGraphics
import Foundation
@testable import CaptureKit

private func makeImage() -> CGImage {
    let cs = CGColorSpaceCreateDeviceRGB()
    let ctx = CGContext(data: nil, width: 8, height: 8, bitsPerComponent: 8,
                        bytesPerRow: 0, space: cs,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.setFillColor(CGColor(red: 0, green: 0, blue: 1, alpha: 1))
    ctx.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
    return ctx.makeImage()!
}

let tempImageWriterTests: [TestCase] = [
    TestCase("writesPNGToTempAndFileExists") { t in
        guard let url = TempImageWriter.writePNG(makeImage(), fileName: "DragTest.png") else {
            t.isTrue(false)
            return
        }
        defer { try? FileManager.default.removeItem(at: url) }
        t.isTrue(FileManager.default.fileExists(atPath: url.path))
        t.equal(url.pathExtension, "png")
        guard let data = try? Data(contentsOf: url) else {
            t.isTrue(false)
            return
        }
        t.equal(Array(data.prefix(4)), [0x89, 0x50, 0x4E, 0x47])
    },
    TestCase("cleanExpiredDeletesOnlyDirectoriesPastTheWindow") { t in
        let root = makeSandbox(); defer { try? FileManager.default.removeItem(at: root) }
        let now = Date()
        guard let stale = t.unwrap(TempImageWriter.writePNG(makeImage(), fileName: "old.png", in: root)),
              let fresh = t.unwrap(TempImageWriter.writePNG(makeImage(), fileName: "new.png", in: root))
        else { return }
        age(stale, to: now.addingTimeInterval(-301))
        age(fresh, to: now.addingTimeInterval(-10))

        t.equal(TempImageWriter.cleanExpired(in: root, olderThan: 300, now: now), 1)
        t.isFalse(FileManager.default.fileExists(atPath: stale.path))
        t.isTrue(FileManager.default.fileExists(atPath: fresh.path))
    },
    TestCase("cleanExpiredKeepsEverythingWhenRetentionIsInfinite") { t in
        let root = makeSandbox(); defer { try? FileManager.default.removeItem(at: root) }
        guard let url = t.unwrap(TempImageWriter.writePNG(makeImage(), fileName: "keep.png", in: root))
        else { return }
        age(url, to: Date(timeIntervalSince1970: 0))   // ancient

        t.equal(TempImageWriter.cleanExpired(in: root, olderThan: nil), 0)
        t.isTrue(FileManager.default.fileExists(atPath: url.path))
    },
    TestCase("cleanExpiredIgnoresFilesItDoesNotOwn") { t in
        let root = makeSandbox(); defer { try? FileManager.default.removeItem(at: root) }
        // A recording mid-GIF-conversion writes straight to the temp root, not into a
        // BetterScreenshot-<UUID> directory. The sweep must not touch it.
        let recording = root.appendingPathComponent("Recording 2026-08-01.mp4")
        FileManager.default.createFile(atPath: recording.path, contents: Data([0x0]))
        let other = root.appendingPathComponent("SomeOtherApp-123", isDirectory: true)
        try? FileManager.default.createDirectory(at: other, withIntermediateDirectories: true)
        try? FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 0)],
                                               ofItemAtPath: other.path)

        t.equal(TempImageWriter.cleanExpired(in: root, olderThan: 10), 0)
        t.isTrue(FileManager.default.fileExists(atPath: recording.path))
        t.isTrue(FileManager.default.fileExists(atPath: other.path))
    },
    TestCase("cleanExpiredRemovesEmptyDirectoriesLeftByEarlierRuns") { t in
        let root = makeSandbox(); defer { try? FileManager.default.removeItem(at: root) }
        let orphan = root.appendingPathComponent("\(TempImageWriter.directoryPrefix)ORPHAN",
                                                 isDirectory: true)
        try? FileManager.default.createDirectory(at: orphan, withIntermediateDirectories: true)
        try? FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 0)],
                                               ofItemAtPath: orphan.path)

        t.equal(TempImageWriter.cleanExpired(in: root, olderThan: 10), 1)
        t.isFalse(FileManager.default.fileExists(atPath: orphan.path))
    },
]

private func makeSandbox() -> URL {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("TempSweepTests-\(UUID().uuidString)", isDirectory: true)
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
}

/// Backdates a written temp PNG (and its directory) so the sweep sees it as old.
private func age(_ fileURL: URL, to date: Date) {
    let fm = FileManager.default
    try? fm.setAttributes([.modificationDate: date], ofItemAtPath: fileURL.path)
    try? fm.setAttributes([.modificationDate: date],
                          ofItemAtPath: fileURL.deletingLastPathComponent().path)
}
