import Foundation
import CoreGraphics

public enum TempImageWriter {
    /// Every temp PNG goes in its own directory named with this prefix. Scoping cleanup to the
    /// prefix is what keeps it away from everything else in `$TMPDIR` — including the
    /// in-progress GIF that `RecordingCoordinator` writes straight to the temp root.
    public static let directoryPrefix = "BetterScreenshot-"

    /// Writes a PNG into a unique temp subdirectory and returns its URL (nil on failure).
    public static func writePNG(_ image: CGImage, fileName: String,
                                in root: URL = FileManager.default.temporaryDirectory) -> URL? {
        guard let data = ImageEncoder.encode(image, as: .png) else { return nil }
        let dir = root.appendingPathComponent("\(directoryPrefix)\(UUID().uuidString)",
                                              isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let url = dir.appendingPathComponent(fileName)
            try data.write(to: url)
            return url
        } catch { return nil }
    }

    /// Deletes `BetterScreenshot-*` temp directories whose newest file is older than
    /// `olderThan`. `nil` means the ∞ retention stop — nothing is deleted. Returns how many
    /// directories were removed.
    ///
    /// Age comes from the newest file inside a directory (or the directory's own date when it
    /// holds nothing), so a directory only goes once everything in it has aged out — a capture
    /// written moments ago is never swept out from under a drag.
    @discardableResult
    public static func cleanExpired(in root: URL = FileManager.default.temporaryDirectory,
                                    olderThan: TimeInterval?, now: Date = Date()) -> Int {
        guard let olderThan else { return 0 }
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(
            at: root, includingPropertiesForKeys: [.contentModificationDateKey, .isDirectoryKey],
            options: [.skipsHiddenFiles]) else { return 0 }

        let cutoff = now.addingTimeInterval(-olderThan)
        var removed = 0
        for dir in items where dir.lastPathComponent.hasPrefix(directoryPrefix) {
            guard (try? dir.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true,
                  newestDate(in: dir) <= cutoff
            else { continue }
            if (try? fm.removeItem(at: dir)) != nil { removed += 1 }
        }
        return removed
    }

    /// Newest modification date among a directory's files, falling back to the directory's own
    /// date when it holds nothing.
    private static func newestDate(in dir: URL) -> Date {
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: [.contentModificationDateKey],
            options: [])) ?? []
        let dates = contents.compactMap {
            (try? $0.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        }
        if let newest = dates.max() { return newest }
        return (try? dir.resourceValues(forKeys: [.contentModificationDateKey]))?
            .contentModificationDate ?? .distantPast
    }
}
