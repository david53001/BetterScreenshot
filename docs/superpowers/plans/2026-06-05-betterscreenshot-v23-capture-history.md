# BetterScreenshot v2.3 Capture History Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Every capture and recording lands in a local, capped, browsable history; an accidentally ✕-closed or evicted Quick Access overlay can be restored.

**Architecture:** New zero-coupling local package **HistoryKit** (Foundation/CoreGraphics/ImageIO only) holding the pure index, restore LIFO, thumbnail renderer, and file-backed store. OverlayKit's Quick Access dismiss path gains a reason (`closed`/`evicted`/`actionTaken`) so the app can track accidental closes. The App target composes: an `HistoryService` façade, coordinator hooks, a History window (SwiftUI `LazyVGrid` in an `NSHostingController` window), menu items, two new unbound hotkey actions, and a Settings section.

**Tech Stack:** Swift 5.9 SwiftPM, TestKit executable runners (NO XCTest/xcodebuild), SwiftUI + AppKit, ImageIO.

**Spec:** `docs/superpowers/specs/2026-06-05-betterscreenshot-capture-history-design.md`. Ends at tag `v2.3-history`.

**Pre-flight already done (2026-06-05):** go/no-go probe passed — `CGImageSourceCreateThumbnailAtIndex` works headless under CLT (1600×1000 → 400×250 aspect-preserved JPEG). All spec symbols verified against live code. `onDismissed` is consumed ONLY by `QuickAccessStackController` — the signature change is safe.

**Owner addition (2026-06-05):** the user reported overlays vanish on 3-finger Spaces swipes in their deployed v2.1 build. The fix (`collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]`, commit d902c80) is already on `main` and ships with this release — the manual checklist (final task) includes an explicit Spaces-swipe verification. No new code needed for it.

**Conventions for every task:**
- Run a task's suite with `swift run --package-path Packages/<Pkg> <Pkg>Tests`; the full gate is `./scripts/test.sh && swift build`.
- Each task ends in one commit.
- Do NOT build background/wallpaper styling (dropped by owner decision).

---

## File Structure

| File | Responsibility |
|---|---|
| `Packages/HistoryKit/Package.swift` | New package manifest (mirrors CaptureKit) |
| `Packages/HistoryKit/Sources/HistoryKit/HistoryEntry.swift` | Codable entry value type + `HistoryKind` |
| `Packages/HistoryKit/Sources/HistoryKit/HistoryIndex.swift` | Pure ordered index: add/cap/age-prune/remove/missing-file prune/JSON |
| `Packages/HistoryKit/Sources/HistoryKit/RestoreStack.swift` | Pure in-memory LIFO of recently-closed overlay entry IDs (depth 5) |
| `Packages/HistoryKit/Sources/HistoryKit/ThumbnailRenderer.swift` | Encoded image data → ≤400 px JPEG via ImageIO |
| `Packages/HistoryKit/Sources/HistoryKit/HistoryStore.swift` | File IO: dir, PNG copy + thumb files, atomic `history.json` |
| `Packages/HistoryKit/Tests/HistoryKitTests/*.swift` + `main.swift` | TestKit suite |
| `Packages/CaptureKit/Sources/CaptureKit/CaptureSettings.swift` | + `historyEnabled`, `historyCap` |
| `Packages/CaptureKit/Sources/CaptureKit/HotkeyAction.swift` | + `.openHistory`, `.restoreRecentlyClosed` (unbound) |
| `Packages/OverlayKit/Sources/OverlayKit/QuickAccessOverlayController.swift` | `DismissReason` + reasoned `dismiss(reason:)` |
| `Packages/OverlayKit/Sources/OverlayKit/QuickAccessStackController.swift` | Forward reason; per-present `onDismissed` callback |
| `App/HistoryService.swift` | App façade: store + LIFO + settings gate + clipboard/reveal helpers |
| `App/CaptureCoordinator.swift` | History add in `handle`; restore tracking; restore re-present |
| `App/RecordingCoordinator.swift` | History add on every finished recording; restore re-present |
| `App/HistoryWindowController.swift` | History window (mirrors SettingsWindowController) + `HistoryView` |
| `App/MenuBarController.swift` | "History…" + "Restore Recently Closed" items + validation |
| `App/SettingsView.swift` / `App/SettingsWindowController.swift` | General-tab History section, `clearHistory` plumbing |
| `App/AppDelegate.swift` | Composition + hotkey handlers + restore flow |
| `scripts/test.sh`, `Package.swift` (root) | Register HistoryKit |

---

### Task 1: HistoryKit scaffold + `HistoryEntry` + `HistoryIndex` (TDD, pure)

**Files:**
- Create: `Packages/HistoryKit/Package.swift`
- Create: `Packages/HistoryKit/Sources/HistoryKit/HistoryEntry.swift`
- Create: `Packages/HistoryKit/Sources/HistoryKit/HistoryIndex.swift`
- Create: `Packages/HistoryKit/Tests/HistoryKitTests/HistoryIndexTests.swift`
- Create: `Packages/HistoryKit/Tests/HistoryKitTests/main.swift`
- Modify: `scripts/test.sh:6`

- [ ] **Step 1: Create the package manifest**

`Packages/HistoryKit/Package.swift`:

```swift
// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "HistoryKit",
    platforms: [.macOS(.v14)],
    products: [.library(name: "HistoryKit", targets: ["HistoryKit"])],
    dependencies: [.package(path: "../TestKit")],
    targets: [
        .target(name: "HistoryKit"),
        // Test suite as an executable runner (XCTest is unavailable under CLT).
        // Run with: swift run --package-path Packages/HistoryKit HistoryKitTests
        .executableTarget(
            name: "HistoryKitTests",
            dependencies: ["HistoryKit", .product(name: "TestKit", package: "TestKit")],
            path: "Tests/HistoryKitTests"
        ),
    ]
)
```

- [ ] **Step 2: Write `HistoryEntry` (needed by the failing tests)**

`Packages/HistoryKit/Sources/HistoryKit/HistoryEntry.swift`:

```swift
import Foundation

public enum HistoryKind: String, Codable, Equatable {
    case screenshot, recording
}

/// One remembered capture. Screenshots own a full-res PNG copy (`imageFile`);
/// recordings reference the user's saved file (`filePath`). Both own a JPEG
/// thumbnail. `imageFile`/`thumbFile` are names relative to the history
/// directory; `filePath` is absolute.
public struct HistoryEntry: Codable, Equatable, Identifiable {
    public let id: UUID
    public let kind: HistoryKind
    public let date: Date
    public let imageFile: String?
    public let filePath: String?
    public let thumbFile: String

    public init(id: UUID = UUID(), kind: HistoryKind, date: Date,
                imageFile: String? = nil, filePath: String? = nil, thumbFile: String) {
        self.id = id; self.kind = kind; self.date = date
        self.imageFile = imageFile; self.filePath = filePath; self.thumbFile = thumbFile
    }
}
```

- [ ] **Step 3: Write the failing index tests**

`Packages/HistoryKit/Tests/HistoryKitTests/HistoryIndexTests.swift` — note: dates are whole seconds so the ISO-8601 JSON round-trip compares equal:

```swift
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
```

`Packages/HistoryKit/Tests/HistoryKitTests/main.swift`:

```swift
import TestKit

// Aggregate every test array in this target here. New test files add their
// `[TestCase]` array to this concatenation.
runTests("HistoryKitTests",
    historyIndexTests
)
```

- [ ] **Step 4: Run to verify failure (HistoryIndex doesn't exist)**

Run: `swift run --package-path Packages/HistoryKit HistoryKitTests`
Expected: compile error — `cannot find 'HistoryIndex' in scope`

- [ ] **Step 5: Implement `HistoryIndex`**

`Packages/HistoryKit/Sources/HistoryKit/HistoryIndex.swift`:

```swift
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
```

- [ ] **Step 6: Run to verify pass**

Run: `swift run --package-path Packages/HistoryKit HistoryKitTests`
Expected: `PASS — HistoryKitTests: 10/10 test(s) passed`

- [ ] **Step 7: Register HistoryKit in the test runner**

`scripts/test.sh` line 6 — change:

```bash
for pkg in CaptureKit OverlayKit EditorKit RecordingKit; do
```

to:

```bash
for pkg in CaptureKit OverlayKit EditorKit RecordingKit HistoryKit; do
```

- [ ] **Step 8: Full gate**

Run: `./scripts/test.sh && swift build`
Expected: `All suites passed.` and a clean build.

- [ ] **Step 9: Commit**

```bash
git add Packages/HistoryKit scripts/test.sh
git commit -m "feat(history): HistoryKit package with pure HistoryIndex (add/cap/prune/JSON)"
```

---

### Task 2: `RestoreStack` + `ThumbnailRenderer` (TDD)

**Files:**
- Create: `Packages/HistoryKit/Sources/HistoryKit/RestoreStack.swift`
- Create: `Packages/HistoryKit/Sources/HistoryKit/ThumbnailRenderer.swift`
- Create: `Packages/HistoryKit/Tests/HistoryKitTests/RestoreStackTests.swift`
- Create: `Packages/HistoryKit/Tests/HistoryKitTests/ThumbnailRendererTests.swift`
- Modify: `Packages/HistoryKit/Tests/HistoryKitTests/main.swift`

- [ ] **Step 1: Write the failing tests**

`Packages/HistoryKit/Tests/HistoryKitTests/RestoreStackTests.swift`:

```swift
import TestKit
import Foundation
@testable import HistoryKit

let restoreStackTests: [TestCase] = [
    TestCase("popReturnsNewestFirst") { t in
        var s = RestoreStack()
        let a = UUID(), b = UUID()
        s.push(a); s.push(b)
        t.equal(s.pop(), b)
        t.equal(s.pop(), a)
        t.isNil(s.pop())
    },
    TestCase("isEmptyTracksContents") { t in
        var s = RestoreStack()
        t.isTrue(s.isEmpty)
        s.push(UUID())
        t.isFalse(s.isEmpty)
        _ = s.pop()
        t.isTrue(s.isEmpty)
    },
    TestCase("depthCapDropsOldest") { t in
        var s = RestoreStack()
        let ids = (0..<6).map { _ in UUID() }
        for id in ids { s.push(id) }
        // ids[0] fell off the bottom; newest five remain in LIFO order.
        for id in ids.dropFirst().reversed() { t.equal(s.pop(), id) }
        t.isNil(s.pop())
    },
    TestCase("repushMovesIDToTop") { t in
        var s = RestoreStack()
        let a = UUID(), b = UUID()
        s.push(a); s.push(b); s.push(a)
        t.equal(s.pop(), a)
        t.equal(s.pop(), b)
        t.isNil(s.pop())
    },
]
```

`Packages/HistoryKit/Tests/HistoryKitTests/ThumbnailRendererTests.swift` — `makePNGData` is shared by Task 3's store tests (file-internal `func`, same target):

```swift
import TestKit
import Foundation
import CoreGraphics
import ImageIO
@testable import HistoryKit

/// A small solid-color PNG for thumbnail/store tests (shared with HistoryStoreTests).
func makePNGData(width: Int = 1600, height: Int = 1000) -> Data {
    let cs = CGColorSpace(name: CGColorSpace.sRGB)!
    let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                        bytesPerRow: 0, space: cs,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.setFillColor(CGColor(red: 0.2, green: 0.4, blue: 0.8, alpha: 1))
    ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
    let img = ctx.makeImage()!
    let out = NSMutableData()
    let dest = CGImageDestinationCreateWithData(out as CFMutableData,
                                                "public.png" as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, img, nil)
    CGImageDestinationFinalize(dest)
    return out as Data
}

let thumbnailRendererTests: [TestCase] = [
    TestCase("capsLongestSideAt400") { t in
        let png = makePNGData(width: 1600, height: 1000)
        guard let thumb = t.unwrap(ThumbnailRenderer.jpegThumbnail(from: png)) else { return }
        guard let size = t.unwrap(ThumbnailRenderer.pixelSize(of: thumb)) else { return }
        t.equal(Int(size.width), 400)
        t.equal(Int(size.height), 250)
    },
    TestCase("smallImagesAreNotUpscaledBeyondCap") { t in
        let png = makePNGData(width: 200, height: 100)
        guard let thumb = t.unwrap(ThumbnailRenderer.jpegThumbnail(from: png)) else { return }
        guard let size = t.unwrap(ThumbnailRenderer.pixelSize(of: thumb)) else { return }
        t.isTrue(size.width <= 400 && size.height <= 400)
    },
    TestCase("outputIsJPEG") { t in
        let png = makePNGData(width: 100, height: 100)
        guard let thumb = t.unwrap(ThumbnailRenderer.jpegThumbnail(from: png)) else { return }
        t.equal(Array(thumb.prefix(2)), [0xFF, 0xD8])
    },
    TestCase("garbageDataReturnsNil") { t in
        t.isNil(ThumbnailRenderer.jpegThumbnail(from: Data([0x00, 0x01, 0x02])))
    },
]
```

Update `main.swift`:

```swift
import TestKit

// Aggregate every test array in this target here. New test files add their
// `[TestCase]` array to this concatenation.
runTests("HistoryKitTests",
    historyIndexTests +
    restoreStackTests +
    thumbnailRendererTests
)
```

- [ ] **Step 2: Run to verify failure**

Run: `swift run --package-path Packages/HistoryKit HistoryKitTests`
Expected: compile error — `cannot find 'RestoreStack' in scope`

- [ ] **Step 3: Implement**

`Packages/HistoryKit/Sources/HistoryKit/RestoreStack.swift`:

```swift
import Foundation

/// In-memory LIFO of recently ✕-closed/evicted overlays, identified by their
/// history entry IDs. Depth-capped; never persisted (cleared on quit by virtue
/// of living in memory).
public struct RestoreStack: Equatable {
    public static let depth = 5
    private var ids: [UUID] = []   // last = newest

    public init() {}

    public var isEmpty: Bool { ids.isEmpty }

    /// Push a newly-closed overlay. Re-pushing an id moves it to the top.
    public mutating func push(_ id: UUID) {
        ids.removeAll { $0 == id }
        ids.append(id)
        if ids.count > Self.depth { ids.removeFirst(ids.count - Self.depth) }
    }

    /// Pop the most recently closed id.
    public mutating func pop() -> UUID? {
        ids.popLast()
    }
}
```

`Packages/HistoryKit/Sources/HistoryKit/ThumbnailRenderer.swift`:

```swift
import Foundation
import CoreGraphics
import ImageIO

/// Downscales encoded image data (PNG, TIFF, …) to a JPEG thumbnail whose
/// longest side is at most `maxPixelSize`. Pure data-in/data-out; works
/// headless (probed 2026-06-05 under CLT).
public enum ThumbnailRenderer {
    public static func jpegThumbnail(from imageData: Data,
                                     maxPixelSize: Int = 400,
                                     quality: Double = 0.8) -> Data? {
        guard let src = CGImageSourceCreateWithData(imageData as CFData, nil) else { return nil }
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            kCGImageSourceCreateThumbnailWithTransform: true,
        ]
        guard let thumb = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary)
        else { return nil }
        let out = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(
            out as CFMutableData, "public.jpeg" as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, thumb,
            [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return out as Data
    }

    /// Pixel size of encoded image data (for tests and sanity checks).
    public static func pixelSize(of imageData: Data) -> CGSize? {
        guard let src = CGImageSourceCreateWithData(imageData as CFData, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
              let w = props[kCGImagePropertyPixelWidth] as? Int,
              let h = props[kCGImagePropertyPixelHeight] as? Int else { return nil }
        return CGSize(width: w, height: h)
    }
}
```

- [ ] **Step 4: Run to verify pass**

Run: `swift run --package-path Packages/HistoryKit HistoryKitTests`
Expected: `PASS — HistoryKitTests: 18/18 test(s) passed`

- [ ] **Step 5: Full gate + commit**

```bash
./scripts/test.sh && swift build
git add Packages/HistoryKit
git commit -m "feat(history): RestoreStack LIFO and ImageIO ThumbnailRenderer"
```

---

### Task 3: `HistoryStore` (TDD, temp-dir probes)

**Files:**
- Create: `Packages/HistoryKit/Sources/HistoryKit/HistoryStore.swift`
- Create: `Packages/HistoryKit/Tests/HistoryKitTests/HistoryStoreTests.swift`
- Modify: `Packages/HistoryKit/Tests/HistoryKitTests/main.swift`

- [ ] **Step 1: Write the failing tests**

`Packages/HistoryKit/Tests/HistoryKitTests/HistoryStoreTests.swift`:

```swift
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
        let store = HistoryStore(directory: dir, cap: 50)
        guard let entry = t.unwrap(store.addScreenshot(pngData: makePNGData(), cap: 50)) else { return }
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
        let store = HistoryStore(directory: dir, cap: 50)
        guard let entry = t.unwrap(store.addRecording(
            filePath: saved.path, thumbnailSource: makePNGData(), cap: 50)) else { return }
        t.equal(entry.kind, .recording)
        t.isNil(entry.imageFile)
        t.equal(entry.filePath, saved.path)
        t.isTrue(FileManager.default.fileExists(atPath: store.thumbURL(for: entry).path))
    },
    TestCase("reloadRoundTripsIndex") { t in
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = HistoryStore(directory: dir, cap: 50)
        store.addScreenshot(pngData: makePNGData(), cap: 50)
        store.addScreenshot(pngData: makePNGData(), cap: 50)
        let reloaded = HistoryStore(directory: dir, cap: 50)
        t.equal(reloaded.index.entries.map(\.id), store.index.entries.map(\.id))
    },
    TestCase("capEvictionDeletesOwnedFiles") { t in
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = HistoryStore(directory: dir, cap: 1)
        guard let first = t.unwrap(store.addScreenshot(pngData: makePNGData(), cap: 1)) else { return }
        let firstImage = store.imageURL(for: first)!
        let firstThumb = store.thumbURL(for: first)
        store.addScreenshot(pngData: makePNGData(), cap: 1)
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
        let store = HistoryStore(directory: dir, cap: 50)
        guard let entry = t.unwrap(store.addRecording(
            filePath: saved.path, thumbnailSource: makePNGData(), cap: 50)) else { return }
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
        let store = HistoryStore(directory: dir, cap: 50)
        guard let e = t.unwrap(store.addScreenshot(pngData: makePNGData(), cap: 50)) else { return }
        let image = store.imageURL(for: e)!
        store.clearAll()
        t.isTrue(store.index.entries.isEmpty)
        t.isFalse(FileManager.default.fileExists(atPath: image.path))
        let reloaded = HistoryStore(directory: dir, cap: 50)
        t.isTrue(reloaded.index.entries.isEmpty)
    },
    TestCase("corruptIndexStartsEmpty") { t in
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? Data("garbage".utf8).write(to: dir.appendingPathComponent("history.json"))
        let store = HistoryStore(directory: dir, cap: 50)
        t.isTrue(store.index.entries.isEmpty)
    },
    TestCase("missingRecordingFilePrunedAtLoad") { t in
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let saved = FileManager.default.temporaryDirectory
            .appendingPathComponent("rec-\(UUID().uuidString).mp4")
        FileManager.default.createFile(atPath: saved.path, contents: Data([0x0]))
        let store = HistoryStore(directory: dir, cap: 50)
        store.addRecording(filePath: saved.path, thumbnailSource: makePNGData(), cap: 50)
        try? FileManager.default.removeItem(at: saved)   // user deletes it in Finder
        let reloaded = HistoryStore(directory: dir, cap: 50)
        t.isTrue(reloaded.index.entries.isEmpty)
    },
    TestCase("agePruneAppliesAtLoad") { t in
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = HistoryStore(directory: dir, cap: 50)
        store.addScreenshot(pngData: makePNGData(), cap: 50,
                            date: Date().addingTimeInterval(-31 * 86_400))
        t.equal(store.index.entries.count, 1)
        let reloaded = HistoryStore(directory: dir, cap: 50)
        t.isTrue(reloaded.index.entries.isEmpty)
    },
    TestCase("savedFileExistsReflectsDisk") { t in
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let saved = FileManager.default.temporaryDirectory
            .appendingPathComponent("rec-\(UUID().uuidString).mp4")
        FileManager.default.createFile(atPath: saved.path, contents: Data([0x0]))
        let store = HistoryStore(directory: dir, cap: 50)
        guard let entry = t.unwrap(store.addRecording(
            filePath: saved.path, thumbnailSource: makePNGData(), cap: 50)) else { return }
        t.isTrue(store.savedFileExists(entry))
        try? FileManager.default.removeItem(at: saved)
        t.isFalse(store.savedFileExists(entry))
    },
]
```

Update `main.swift` aggregation to:

```swift
runTests("HistoryKitTests",
    historyIndexTests +
    restoreStackTests +
    thumbnailRendererTests +
    historyStoreTests
)
```

- [ ] **Step 2: Run to verify failure**

Run: `swift run --package-path Packages/HistoryKit HistoryKitTests`
Expected: compile error — `cannot find 'HistoryStore' in scope`

- [ ] **Step 3: Implement `HistoryStore`**

`Packages/HistoryKit/Sources/HistoryKit/HistoryStore.swift`:

```swift
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
```

- [ ] **Step 4: Run to verify pass**

Run: `swift run --package-path Packages/HistoryKit HistoryKitTests`
Expected: `PASS — HistoryKitTests: 28/28 test(s) passed`

- [ ] **Step 5: Full gate + commit**

```bash
./scripts/test.sh && swift build
git add Packages/HistoryKit
git commit -m "feat(history): file-backed HistoryStore with retention and atomic index writes"
```

---

### Task 4: CaptureKit — settings keys + hotkey actions (TDD)

**Files:**
- Modify: `Packages/CaptureKit/Sources/CaptureKit/CaptureSettings.swift`
- Modify: `Packages/CaptureKit/Sources/CaptureKit/HotkeyAction.swift`
- Modify: `Packages/CaptureKit/Tests/CaptureKitTests/CaptureSettingsTests.swift`
- Modify: `Packages/CaptureKit/Tests/CaptureKitTests/HotkeyTests.swift`

- [ ] **Step 1: Write the failing tests**

Append to the array in `CaptureSettingsTests.swift` (after the `roundTripsPinFields` case):

```swift
    TestCase("historyDefaults") { t in
        let s = CaptureSettings.default
        t.isTrue(s.historyEnabled)
        t.equal(s.historyCap, 50)
    },
    TestCase("roundTripsHistoryFields") { t in
        var s = CaptureSettings.default
        s.historyEnabled = false
        s.historyCap = 200
        let restored = CaptureSettings(dictionary: s.dictionary)
        t.equal(restored, s)
    },
```

In `HotkeyTests.swift`, append to `hotkeyBindingsTests`:

```swift
    TestCase("historyActionsUnboundByDefault") { t in
        t.isNil(HotkeyAction.openHistory.defaultCombo)
        t.isNil(HotkeyAction.restoreRecentlyClosed.defaultCombo)
        t.equal(HotkeyAction.openHistory.title, "Open History")
        t.equal(HotkeyAction.restoreRecentlyClosed.title, "Restore Recently Closed")
        t.isNil(HotkeyBindings.defaults.combo(for: .openHistory))
        t.isNil(HotkeyBindings.defaults.combo(for: .restoreRecentlyClosed))
    },
```

And in the existing `recordActionDefaults` case, replace:

```swift
        // record comes last in allCases (menu/settings row order).
        t.equal(HotkeyAction.allCases.last, .record)
```

with:

```swift
        // history actions come after record in allCases (menu/settings row order).
        t.equal(HotkeyAction.allCases.last, .restoreRecentlyClosed)
```

- [ ] **Step 2: Run to verify failure**

Run: `swift run --package-path Packages/CaptureKit CaptureKitTests`
Expected: compile error — `type 'HotkeyAction' has no member 'openHistory'` (and missing `historyEnabled`)

- [ ] **Step 3: Implement**

`CaptureSettings.swift` — full replacement of the struct body pieces:

```swift
public struct CaptureSettings: Equatable {
    public var afterCapture: AfterCaptureBehavior
    public var format: SettingsImageFormat
    public var overlayCorner: OverlayCorner
    public var overlayAutoDismissSeconds: Int
    public var pinCornerRadius: Int
    public var pinShadow: Bool
    public var historyEnabled: Bool
    public var historyCap: Int

    public static let `default` = CaptureSettings(
        afterCapture: .showOverlay, format: .png,
        overlayCorner: .bottomRight, overlayAutoDismissSeconds: 6)

    public var dictionary: [String: String] {
        ["afterCapture": afterCapture.rawValue,
         "format": format.rawValue,
         "overlayCorner": overlayCorner.rawValue,
         "overlayAutoDismissSeconds": String(overlayAutoDismissSeconds),
         "pinCornerRadius": String(pinCornerRadius),
         "pinShadow": pinShadow ? "true" : "false",
         "historyEnabled": historyEnabled ? "true" : "false",
         "historyCap": String(historyCap)]
    }

    public init(afterCapture: AfterCaptureBehavior, format: SettingsImageFormat,
                overlayCorner: OverlayCorner, overlayAutoDismissSeconds: Int,
                pinCornerRadius: Int = 8, pinShadow: Bool = true,
                historyEnabled: Bool = true, historyCap: Int = 50) {
        self.afterCapture = afterCapture
        self.format = format
        self.overlayCorner = overlayCorner
        self.overlayAutoDismissSeconds = overlayAutoDismissSeconds
        self.pinCornerRadius = pinCornerRadius
        self.pinShadow = pinShadow
        self.historyEnabled = historyEnabled
        self.historyCap = historyCap
    }

    public init(dictionary: [String: String]) {
        let d = CaptureSettings.default
        self.afterCapture = AfterCaptureBehavior(rawValue: dictionary["afterCapture"] ?? "") ?? d.afterCapture
        self.format = SettingsImageFormat(rawValue: dictionary["format"] ?? "") ?? d.format
        self.overlayCorner = OverlayCorner(rawValue: dictionary["overlayCorner"] ?? "") ?? d.overlayCorner
        self.overlayAutoDismissSeconds = Int(dictionary["overlayAutoDismissSeconds"] ?? "") ?? d.overlayAutoDismissSeconds
        self.pinCornerRadius = Int(dictionary["pinCornerRadius"] ?? "") ?? d.pinCornerRadius
        self.pinShadow = dictionary["pinShadow"].map { $0 == "true" } ?? d.pinShadow
        self.historyEnabled = dictionary["historyEnabled"].map { $0 == "true" } ?? d.historyEnabled
        self.historyCap = Int(dictionary["historyCap"] ?? "") ?? d.historyCap
    }
}
```

`HotkeyAction.swift` — full replacement:

```swift
import Foundation

/// Every user-bindable action. Raw values are the persistence keys — don't rename.
public enum HotkeyAction: String, CaseIterable, Hashable {
    case captureArea, captureWindow, captureFullscreen, captureText, pinFromClipboard, record,
         openHistory, restoreRecentlyClosed

    public var title: String {
        switch self {
        case .captureArea:           return "Capture Area"
        case .captureWindow:         return "Capture Window"
        case .captureFullscreen:     return "Capture Fullscreen"
        case .captureText:           return "Capture Text"
        case .pinFromClipboard:      return "Pin from Clipboard"
        case .record:                return "Start/Stop Recording"
        case .openHistory:           return "Open History"
        case .restoreRecentlyClosed: return "Restore Recently Closed"
        }
    }

    /// Defaults: ⌘⇧4 area · ⌘⇧6 fullscreen · ⌘⇧7 text · ⌘⇧8 window · ⌘⇧5 record ·
    /// pin/history/restore unbound (bindable in the Shortcuts tab).
    public var defaultCombo: HotkeyCombo? {
        let cmdShift = HotkeyCombo.commandMask | HotkeyCombo.shiftMask
        switch self {
        case .captureArea:       return HotkeyCombo(keyCode: 21, modifiers: cmdShift) // ⌘⇧4
        case .captureWindow:     return HotkeyCombo(keyCode: 28, modifiers: cmdShift) // ⌘⇧8
        case .captureFullscreen: return HotkeyCombo(keyCode: 22, modifiers: cmdShift) // ⌘⇧6
        case .captureText:       return HotkeyCombo(keyCode: 26, modifiers: cmdShift) // ⌘⇧7
        case .pinFromClipboard:  return nil
        case .record:            return HotkeyCombo(keyCode: 23, modifiers: cmdShift) // ⌘⇧5
        case .openHistory:           return nil
        case .restoreRecentlyClosed: return nil
        }
    }
}
```

- [ ] **Step 4: Run to verify pass, then full gate**

Run: `swift run --package-path Packages/CaptureKit CaptureKitTests`
Expected: PASS, all cases.
Run: `./scripts/test.sh && swift build`
Expected: all suites + app build green (nothing switches exhaustively over `HotkeyAction` outside CaptureKit; the Shortcuts tab and menus use `allCases`/dictionaries).

- [ ] **Step 5: Commit**

```bash
git add Packages/CaptureKit
git commit -m "feat(capture-kit): history settings keys and two unbound history hotkey actions"
```

---

### Task 5: OverlayKit — dismiss reasons

No new TestKit tests (AppKit panel behavior — covered by the manual checklist); the gate is compilation + existing suites.

**Files:**
- Modify: `Packages/OverlayKit/Sources/OverlayKit/QuickAccessOverlayController.swift`
- Modify: `Packages/OverlayKit/Sources/OverlayKit/QuickAccessStackController.swift`

- [ ] **Step 1: Add `DismissReason` and thread it through the overlay controller**

In `QuickAccessOverlayController.swift`, insert above the class (after the `QuickAccessKind` enum):

```swift
/// Why a Quick Access overlay went away. `closed` (✕) and `evicted` (pushed
/// out by newer captures) are "accidental" — eligible for Restore Recently
/// Closed. `actionTaken` (save, annotate, pin, open, reveal, drag-out) is
/// deliberate and is not restorable.
public enum DismissReason: Equatable {
    case closed, evicted, actionTaken
}
```

Change the callback declaration (line 44):

```swift
    /// Fired exactly once whenever a visible overlay goes away (✕, save,
    /// drag-out, annotate, pin, or eviction) so a stack manager can compact
    /// and the app can track restorable closes.
    public var onDismissed: ((DismissReason) -> Void)?
```

Change `dismiss` (line 117):

```swift
    public func dismiss(reason: DismissReason = .actionTaken) {
        guard panel != nil else { return }
        panel?.orderOut(nil); panel = nil; actions = nil
        onDismissed?(reason)
    }
```

Update every internal call site:
- in `present(...)` line 51: `dismiss()` → `dismiss(reason: .evicted)` (a re-present replaces the old card)
- drag-ended closure line 89: `self?.dismiss()` → `self?.dismiss(reason: .actionTaken)`
- `saveAction` line 143: `dismiss()` → `dismiss(reason: .actionTaken)`
- `annotateAction`, `pinAction`, `openAction`, `revealAction`: `dismiss()` → `dismiss(reason: .actionTaken)`
- `closeAction` line 168: `dismiss()` → `dismiss(reason: .closed)`

- [ ] **Step 2: Forward the reason through the stack + add per-present callback**

`QuickAccessStackController.swift` — replace `present` with:

```swift
    public func present(image: NSImage, kind: QuickAccessKind = .screenshot,
                        actions: QuickAccessActions,
                        onDismissed: ((DismissReason) -> Void)? = nil,
                        originForIndex: @escaping (Int) -> CGPoint) {
        self.originForIndex = originForIndex
        if entries.count == maxCount, let oldest = entries.last {
            entries.removeLast()
            oldest.dismiss(reason: .evicted)   // stack bookkeeping no-ops: already removed
        }
        let controller = QuickAccessOverlayController()
        controller.onDismissed = { [weak self, weak controller] reason in
            onDismissed?(reason)
            guard let self, let controller else { return }
            self.entries.removeAll { $0 === controller }
            self.restack()
        }
        entries.insert(controller, at: 0)
        controller.present(image: image, at: originForIndex(0), kind: kind, actions: actions)
        restack()
    }
```

(The new `onDismissed` parameter defaults to `nil`, so the existing App call sites compile unchanged until Task 6 wires them.)

- [ ] **Step 3: Full gate**

Run: `./scripts/test.sh && swift build`
Expected: all suites pass; the app target still compiles (it never referenced `onDismissed` or called `dismiss` directly — verified by grep on 2026-06-05).

- [ ] **Step 4: Commit**

```bash
git add Packages/OverlayKit
git commit -m "feat(overlay): dismiss reasons (closed/evicted/actionTaken) on Quick Access overlays"
```

---### Task 6: App — `HistoryService` + coordinator hooks

App-target glue (no TestKit coverage — gate is `swift build` + existing suites; behavior lands on the manual checklist).

**Files:**
- Create: `App/HistoryService.swift`
- Modify: `Package.swift` (root — add HistoryKit)
- Modify: `App/CaptureCoordinator.swift`
- Modify: `App/RecordingCoordinator.swift`
- Modify: `App/AppDelegate.swift`

- [ ] **Step 1: Register HistoryKit in the root manifest**

In root `Package.swift`, add to `dependencies`:

```swift
        .package(path: "Packages/HistoryKit"),
```

and to the executable target's `dependencies`:

```swift
                .product(name: "HistoryKit", package: "HistoryKit"),
```

- [ ] **Step 2: Create `HistoryService`**

`App/HistoryService.swift`:

```swift
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
            NSPasteboard.general.writeObjects([img])
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
```

- [ ] **Step 3: Hook `CaptureCoordinator`**

In `App/CaptureCoordinator.swift`:

Add after the `presentSetup` property (line ~22):

```swift
    /// Set by the app delegate; nil until then (history silently skipped).
    var history: HistoryService?
```

Replace `handle(_:sourceRect:)`:

```swift
    private func handle(_ image: CGImage, sourceRect: CGRect?) {
        // Silent bookkeeping first, so even copy-only captures are recoverable.
        let historyID = history?.recordScreenshot(image)
        switch settings.settings.afterCapture {
        case .copyOnly:    copy(image)
        case .saveOnly:    save(image)
        case .copyAndSave: copy(image); save(image)
        case .showOverlay: presentOverlay(image, sourceRect: sourceRect, historyID: historyID)
        }
    }
```

Replace `presentOverlay` signature and the `quickAccess.present` call:

```swift
    private func presentOverlay(_ image: CGImage, sourceRect: CGRect?, historyID: UUID?) {
        let nsImage = NSImage(cgImage: image,
                              size: NSSize(width: image.width, height: image.height))
        guard let screen = NSScreen.main else { copy(image); save(image); return }
        let actions = QuickAccessActions(
            onCopy: { [weak self] in self?.copy(image); self?.hud.show("Copied") },
            // The overlay's download button always lands in the macOS screenshot folder.
            onSave: { [weak self] in self?.save(image, to: SettingsStore.systemScreenshotLocation()) },
            onAnnotate: { [weak self] in self?.annotate(image) },
            onPin: { [weak self] in self?.pin(image, near: sourceRect) },
            fileURLForDrag: { TempImageWriter.writePNG(image, fileName: FileNamer.fileName(for: Date(), ext: "png")) })
        let corner = settings.settings.overlayCorner
        // visibleFrame excludes the Dock and menu bar, so the overlay sits above
        // the Dock instead of being tucked into the very bottom corner behind it.
        let frame = screen.visibleFrame
        quickAccess.present(image: nsImage, actions: actions, onDismissed: { [weak self] reason in
            // ✕-close and eviction are "accidental" — deliberate actions aren't restorable.
            if reason == .closed || reason == .evicted {
                self?.history?.noteOverlayClosed(historyID: historyID)
            }
        }) { index in
            OverlayPositioner.stackedOrigin(corner: corner,
                                            overlaySize: CGSize(width: 220, height: 168),
                                            screenFrame: frame, margin: 24, index: index)
        }
    }

    /// Re-presents a Quick Access card for a history entry (Restore Recently Closed).
    func presentOverlayFromHistory(_ image: CGImage, historyID: UUID) {
        presentOverlay(image, sourceRect: nil, historyID: historyID)
    }
```

- [ ] **Step 4: Hook `RecordingCoordinator`**

In `App/RecordingCoordinator.swift`:

Add after `onStateChange` (line ~30):

```swift
    /// Set by the app delegate; nil until then (history silently skipped).
    var history: HistoryService?
```

In `stop()`, replace the four save-path branches so EVERY finished recording lands in history (GIF success, GIF-fallback MP4, terminating GIF→MP4, and plain MP4):

```swift
            let mp4 = try await recorder.stop()
            tearDownPanels()
            if config.format == .gif, !isTerminating {
                hud.show("Converting to GIF…")
                let gifName = FileNamer.fileName(for: Date(), ext: "gif", prefix: "Recording")
                let gifURL = settings.saveDirectory.appendingPathComponent(gifName)
                do {
                    try await GIFExporter.export(mp4: mp4, to: gifURL)
                    try? FileManager.default.removeItem(at: mp4)
                    await finishRecording(at: gifURL)
                } catch {
                    // Keep the MP4 so the recording isn't lost.
                    let mp4Name = FileNamer.fileName(for: Date(), ext: "mp4", prefix: "Recording")
                    let dest = settings.saveDirectory.appendingPathComponent(mp4Name)
                    try? FileManager.default.moveItem(at: mp4, to: dest)
                    await finishRecording(at: dest, showCard: false)
                    hud.show("Saved as MP4 (GIF conversion failed)")
                }
            } else if config.format == .gif {
                // Quitting: no time for conversion — keep the MP4 so nothing is lost.
                let mp4Name = FileNamer.fileName(for: Date(), ext: "mp4", prefix: "Recording")
                let dest = settings.saveDirectory.appendingPathComponent(mp4Name)
                try? FileManager.default.moveItem(at: mp4, to: dest)
                await finishRecording(at: dest, showCard: false)
            } else {
                await finishRecording(at: mp4, showCard: !isTerminating)
            }
```

Replace `presentQuickAccess(for:)` with the three methods below (keep `Self.thumbnail(for:)` as is):

```swift
    /// Post-save tail for every finished recording: add it to capture history,
    /// then show the bottom-corner thumbnail card (suppressed while quitting
    /// and on GIF-fallback saves, which keep their explanatory HUD). Falls
    /// back to a HUD when no frame could be extracted (e.g. zero-length file).
    private func finishRecording(at url: URL, showCard: Bool = true) async {
        guard let image = await Self.thumbnail(for: url) else {
            if showCard { hud.show("Recording saved") }
            return
        }
        let historyID = history?.recordRecording(fileURL: url, thumbnailSource: image)
        if showCard { presentCard(for: url, image: image, historyID: historyID) }
    }

    /// Re-presents a card for a history entry (Restore Recently Closed).
    func presentCardFromHistory(url: URL, image: NSImage, historyID: UUID) {
        presentCard(for: url, image: image, historyID: historyID)
    }

    private func presentCard(for url: URL, image: NSImage, historyID: UUID?) {
        guard let screen = NSScreen.main else { return }
        let actions = QuickAccessActions(
            onCopy: { [weak self] in
                NSPasteboard.general.clearContents()
                NSPasteboard.general.writeObjects([url as NSURL])
                self?.hud.show("File copied")
            },
            onOpen: { NSWorkspace.shared.open(url) },
            onReveal: { NSWorkspace.shared.activateFileViewerSelecting([url]) },
            fileURLForDrag: { url })
        let corner = settings.settings.overlayCorner
        // visibleFrame excludes the Dock and menu bar, so the overlay sits above
        // the Dock instead of being tucked into the very bottom corner behind it.
        let frame = screen.visibleFrame
        quickAccess.present(image: image, kind: .recording, actions: actions,
                            onDismissed: { [weak self] reason in
            if reason == .closed || reason == .evicted {
                self?.history?.noteOverlayClosed(historyID: historyID)
            }
        }) { index in
            OverlayPositioner.stackedOrigin(corner: corner,
                                            overlaySize: CGSize(width: 220, height: 168),
                                            screenFrame: frame, margin: 24, index: index)
        }
    }
```

- [ ] **Step 5: Wire the service in `AppDelegate`**

In `App/AppDelegate.swift`, add a property after `private let hotKeys = HotKeyManager()`:

```swift
    private var history: HistoryService!
```

In `applicationDidFinishLaunching`, right after `let quickAccess = QuickAccessStackController()`:

```swift
        history = HistoryService(settings: settings)
```

and after the two coordinators are created:

```swift
        coordinator.history = history
        recordingCoordinator.history = history
```

- [ ] **Step 6: Full gate + commit**

Run: `swift build && ./scripts/test.sh`
Expected: clean build, all suites pass.

```bash
git add Package.swift App/HistoryService.swift App/CaptureCoordinator.swift App/RecordingCoordinator.swift App/AppDelegate.swift
git commit -m "feat(app): HistoryService façade; every capture and recording lands in history"
```

---

### Task 7: App — History window (`HistoryWindowController` + `HistoryView`)

**Files:**
- Create: `App/HistoryWindowController.swift`
- Modify: `App/AppDelegate.swift`

- [ ] **Step 1: Create the window controller + SwiftUI view**

`App/HistoryWindowController.swift`:

```swift
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
```

- [ ] **Step 2: Instantiate it in `AppDelegate`**

Add a property after `private var settingsWindow: SettingsWindowController!`:

```swift
    private var historyWindow: HistoryWindowController!
```

In `applicationDidFinishLaunching`, right after `coordinator.history = history` / `recordingCoordinator.history = history`:

```swift
        historyWindow = HistoryWindowController(history: history, actions: HistoryWindowActions(
            annotate: { [weak self] image in self?.coordinator.annotate(image) },
            pin: { [weak self] image in self?.coordinator.pin(image) }))
```

(The window is reachable in the next task via menu + hotkey.)

- [ ] **Step 3: Full gate + commit**

Run: `swift build && ./scripts/test.sh`
Expected: clean build, all suites pass.

```bash
git add App/HistoryWindowController.swift App/AppDelegate.swift
git commit -m "feat(app): History window — thumbnail grid with per-item actions"
```

---

### Task 8: App — menu items, hotkey handlers, restore flow

**Files:**
- Modify: `App/MenuBarController.swift`
- Modify: `App/AppDelegate.swift`

- [ ] **Step 1: Menu items + validation**

In `App/MenuBarController.swift`:

Add callback properties after `var onToggleRecording: (() -> Void)?` (line ~64):

```swift
    var onOpenHistory: (() -> Void)?
    var onRestoreRecentlyClosed: (() -> Void)?
    /// Menu validation: false disables "Restore Recently Closed".
    var canRestore: (() -> Bool)?
```

In `buildMenu()`, after `add("Pin from Clipboard", #selector(pinClipboard), .pinFromClipboard)`:

```swift
        menu.addItem(.separator())
        add("History…", #selector(openHistory), .openHistory)
        add("Restore Recently Closed", #selector(restoreClosed), .restoreRecentlyClosed)
```

Add the selectors next to `pinClipboard`:

```swift
    @objc private func openHistory() { onOpenHistory?() }
    @objc private func restoreClosed() { onRestoreRecentlyClosed?() }
```

Extend `validateMenuItem`:

```swift
    nonisolated func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        MainActor.assumeIsolated {
            if menuItem.action == #selector(pinClipboard) { return coordinator.clipboardHasImage }
            if menuItem.action == #selector(restoreClosed) { return canRestore?() ?? false }
            return true
        }
    }
```

- [ ] **Step 2: AppDelegate — restore flow, menu wiring, hotkey handlers**

In `App/AppDelegate.swift`, after `menuBar.onToggleRecording = ...`:

```swift
        menuBar.onOpenHistory = { [weak self] in self?.historyWindow.show() }
        menuBar.onRestoreRecentlyClosed = { [weak self] in self?.restoreRecentlyClosed() }
        menuBar.canRestore = { [weak self] in self?.history.canRestore ?? false }
```

Add to the `handlers` dictionary in `applyBindings()`:

```swift
            .openHistory:           { [weak self] in Task { @MainActor in self?.historyWindow.show() } },
            .restoreRecentlyClosed: { [weak self] in Task { @MainActor in self?.restoreRecentlyClosed() } },
```

Add the restore method after `restoreDefaultBindings()`:

```swift
    /// Re-presents the most recently ✕-closed/evicted Quick Access overlay
    /// from its history entry (screenshots: stored full-res image; recordings:
    /// saved file + stored thumbnail).
    private func restoreRecentlyClosed() {
        guard let entry = history.popRestorable() else { return }
        switch entry.kind {
        case .screenshot:
            guard let image = history.image(for: entry) else { return }
            coordinator.presentOverlayFromHistory(image, historyID: entry.id)
        case .recording:
            guard let url = history.savedFileURL(for: entry),
                  let image = history.thumbnail(for: entry) else { return }
            recordingCoordinator.presentCardFromHistory(url: url, image: image,
                                                        historyID: entry.id)
        }
    }
```

`AppDelegate.swift` also needs `import HistoryKit` (for `HistoryEntry`'s kind switch — add it next to `import OverlayKit`).

- [ ] **Step 3: Full gate + commit**

Run: `swift build && ./scripts/test.sh`
Expected: clean build, all suites pass.

```bash
git add App/MenuBarController.swift App/AppDelegate.swift
git commit -m "feat(app): History menu items, bindable hotkeys, Restore Recently Closed flow"
```

---

### Task 9: App — Settings "History" section

**Files:**
- Modify: `App/SettingsView.swift`
- Modify: `App/SettingsWindowController.swift`
- Modify: `App/AppDelegate.swift`

- [ ] **Step 1: Thread a `clearHistory` closure into the Settings window**

`App/SettingsWindowController.swift` — add the stored closure and init param:

```swift
@MainActor
final class SettingsWindowController {
    private var window: NSWindow?
    private let store: SettingsStore
    private let shortcuts: ShortcutActions
    private let clearHistory: () -> Void

    init(store: SettingsStore, shortcuts: ShortcutActions, clearHistory: @escaping () -> Void) {
        self.store = store
        self.shortcuts = shortcuts
        self.clearHistory = clearHistory
    }
```

and pass it through in `show()`:

```swift
            let view = SettingsView(store: store, shortcuts: shortcuts, clearHistory: clearHistory)
```

In `App/AppDelegate.swift`, update the construction:

```swift
        settingsWindow = SettingsWindowController(store: settings, shortcuts: shortcuts,
                                                  clearHistory: { [weak self] in
            self?.history.clearAll()
        })
```

- [ ] **Step 2: Add the section to the General tab**

In `App/SettingsView.swift`:

```swift
struct SettingsView: View {
    @ObservedObject var store: SettingsStore
    let shortcuts: ShortcutActions
    let clearHistory: () -> Void

    var body: some View {
        TabView {
            GeneralTab(store: store, clearHistory: clearHistory)
                .tabItem { Label("General", systemImage: "gearshape") }
            ...
```

In `GeneralTab`, add the properties:

```swift
private struct GeneralTab: View {
    @ObservedObject var store: SettingsStore
    let clearHistory: () -> Void
    @State private var launchAtLogin = LaunchAtLogin.isEnabled
    @State private var confirmingClear = false
```

and append inside the `Form`, after the "Save to:" `HStack`:

```swift
            Divider()
            Toggle("Keep capture history", isOn: bind(\.historyEnabled))
            Picker("Keep last", selection: bind(\.historyCap)) {
                Text("10 items").tag(10)
                Text("50 items").tag(50)
                Text("200 items").tag(200)
            }
            .disabled(!store.settings.historyEnabled)
            HStack {
                Text("History keeps full-resolution screenshot copies — they can be several MB each.")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Clear History…") { confirmingClear = true }
            }
            .confirmationDialog("Clear all capture history?",
                                isPresented: $confirmingClear, titleVisibility: .visible) {
                Button("Clear History", role: .destructive) { clearHistory() }
            } message: {
                Text("Removes every remembered capture and its stored copies. Saved recording files on disk are not deleted.")
            }
```

- [ ] **Step 3: Full gate + commit**

Run: `swift build && ./scripts/test.sh`
Expected: clean build, all suites pass.

```bash
git add App/SettingsView.swift App/SettingsWindowController.swift App/AppDelegate.swift
git commit -m "feat(app): History settings — keep toggle, cap picker, Clear History"
```

---

### Task 10: Ship — docs, version bump, tag, push, CI

**Files:**
- Modify: `CHANGELOG.md`, `README.md`, `CLAUDE.md`, `App/Info.plist`

- [ ] **Step 1: CHANGELOG entry** — insert at the top of the release list in `CHANGELOG.md` (after the intro line):

```markdown
## v2.3.0 — 2026-06-05 · Capture history

- **Capture History.** Every screenshot (including copy-only captures that used
  to vanish with the clipboard) and every finished recording is remembered
  locally — browse them in the new **History…** window from the menu bar:
  thumbnail grid, copy / annotate / pin / show-in-Finder / delete per item,
  double-click to edit (screenshots) or play (recordings).
- **Restore Recently Closed.** Accidentally ✕-closed (or stack-evicted) Quick
  Access thumbnails can be brought back from the menu bar; deliberate actions
  (save, annotate, pin, drag-out) don't count as accidental.
- **Settings → General → History:** keep-history toggle, 10/50/200 item cap,
  and Clear History. Retention also prunes entries older than 30 days. All
  local — history lives in `~/Library/Application Support/BetterScreenshot/History/`.
- Both new commands are bindable hotkeys (unbound by default) in
  Settings → Shortcuts.
```

- [ ] **Step 2: README** — in the Features list, after the Quick Access overlay bullet, add:

```markdown
- **Capture History** — every capture and recording is remembered locally (capped + 30-day prune); browse, copy, annotate, pin, or delete from the History window, and restore an accidentally closed thumbnail with Restore Recently Closed
```

and update the test-suite line:

```sh
./scripts/test.sh    # all five suites: CaptureKit, OverlayKit, EditorKit, RecordingKit, HistoryKit
```

- [ ] **Step 3: CLAUDE.md roadmap** — mark v2.3 shipped:
  - In the **Roadmap** intro line append: `· ~~v2.3 capture history~~ (shipped 2026-06-05)`.
  - In the **Next up** numbered list, remove item 1 (v2.3 Capture History) and renumber so v2.4 Recording Controls is 1 and v2.5 Trim Editor is 2.
  - In **Architecture (v1)** package list, add: `` `HistoryKit` — capture history index/store + restore stack (pure logic + file IO). ``

- [ ] **Step 4: Version bump** — `App/Info.plist`: `CFBundleShortVersionString` `2.2.0` → `2.3.0`, `CFBundleVersion` `2` → `3`.

- [ ] **Step 5: Full verification**

```bash
swift build && ./scripts/test.sh && ./scripts/build-app.sh
```
Expected: all suites pass; `dist/BetterScreenshot.app` assembled.

- [ ] **Step 6: Commit, tag, push, watch CI**

```bash
git add CHANGELOG.md README.md CLAUDE.md App/Info.plist
git commit -m "chore: bump app version to 2.3.0 for the capture history release"
git tag v2.3-history
git push origin main --tags
gh run watch $(gh run list --branch main --limit 1 --json databaseId --jq '.[0].databaseId') --exit-status
```
Expected: CI green.

---

## Manual GUI checklist (owner verifies after deploying dist/BetterScreenshot.app → /Applications)

From the spec, plus the owner's Spaces-swipe report:

1. Copy-only capture appears in History.
2. Recording appears in History with working Show in Finder.
3. Cap eviction at 10 (set the cap low for the test).
4. Clear History empties the window and `~/Library/Application Support/BetterScreenshot/History/`.
5. Restore Recently Closed brings back a ✕-closed overlay but NOT a saved one.
6. "Keep capture history" off stops new entries (existing ones remain).
7. Annotate-from-history opens the editor.
8. "file missing" badge after deleting a recording in Finder; entry pruned on next launch.
9. History window resize/grid reflow; dark mode.
10. **Spaces:** take a screenshot, 3-finger-swipe to another desktop — the bottom-corner thumbnail stack must stay visible (fix shipped in v2.2 code, commit d902c80; the deployed v2.1 build predates it).
11. Bind hotkeys for "Open History" / "Restore Recently Closed" in Settings → Shortcuts and confirm they fire.
