# Port Reference — HistoryKit (ground truth for the C#/.NET port)

Source = Swift `Packages/HistoryKit`. Target namespace `BetterScreenshot.History`.
Pure logic + file IO only; the History **window UI** lives in the App layer.

## Data model — HistoryEntry (Codable/JSON)
```
id:        Guid
kind:      "screenshot" | "recording"
date:      DateTime (ISO-8601)
imageFile: string?   // history-owned PNG filename; screenshots only
filePath:  string?   // absolute path to user's saved recording; recordings only (NEVER deleted by history)
thumbFile: string    // history-owned JPEG thumbnail filename; ALWAYS present
```
Invariants: screenshot ⇒ imageFile set, filePath null. recording ⇒ filePath set, imageFile null.
Both ⇒ thumbFile set.

## Persistence
- Dir (mac): `~/Library/Application Support/BetterScreenshot/History/`.
  **Windows:** `%APPDATA%\BetterScreenshot\History\` (`Environment.SpecialFolder.ApplicationData`).
- Index file: `history.json` — pretty-printed, **sorted keys**, ISO-8601 dates, atomic write (temp+rename).
- Owned files: screenshot `{guid}.png`, thumbnail `{guid}-thumb.jpg`.
- Corrupt JSON ⇒ log + start empty (never crash).

## HistoryIndex (PURE, immutable; mutations return (newIndex, evicted[]))
- `entries` newest-first.
- `maxAge = 30 days` (2,592,000 s).
- `adding(entry, cap, now)`: insert at front, then prune → returns evicted list for file cleanup.
- `pruned(cap, now)`: keep entries with `date >= now-30d` AND only newest `cap`. **Exactly-30-days-old survives** (`>=`).
- `removing(id)`, `prunedOfMissingFiles(existsPredicate)`, `jsonData()`/`init(jsonData)`.

## HistoryStore (file-backed)
- `init(dir, cap, now)`: load or empty; apply age+cap+missing-file prune at load; delete evicted owned files.
- `addScreenshot(pngData, cap, date)`: write `{guid}.png` + JPEG thumb + index; return entry (null on IO failure, clean orphans).
- `addRecording(filePath, thumbnailSource, cap, date)`: write thumb only; store reference; never copy video.
- `entry(id)`, `thumbURL`, `imageURL` (screenshots), `savedFileURL`/`savedFileExists` (recordings, live disk check).
- `remove(id)`: delete owned files (image+thumb) but NEVER the recording's saved file.
- `clearAll()`: empty index + delete all owned files; persist empty.

## RestoreStack (in-memory LIFO, NOT persisted)
- `depth = 5`. `push` (re-push moves to top), `pop` (newest first), `isEmpty`.
- Tracks only ✕-closed / evicted overlays (DismissReason .closed/.evicted). Deliberate actions (save/annotate/pin/drag/reveal) do NOT push.
- `popRestorable()`: pop, verify entry still exists in history, else keep popping; returns restorable entry or null.

## ThumbnailRenderer
- `jpegThumbnail(imageData, maxPixelSize=400, quality=0.8)`: downscale longest side ≤400, JPEG @80%, preserve aspect, don't upscale beyond cap.
- Windows: `System.Drawing`/`WIC`/`SkiaSharp`. Output must be valid JPEG (`FF D8`).

## Constants
| Constant | Value |
|---|---|
| maxAge | 30 days |
| RestoreStack depth | 5 |
| thumbnail max side | 400 px |
| thumbnail JPEG quality | 0.8 |
| default historyCap (App) | 50 |
| default historyEnabled | true |
| index file | `history.json` |
| screenshot file | `{guid}.png` |
| thumb file | `{guid}-thumb.jpg` |

## Test suites to re-create (xUnit) — 28 tests
HistoryIndex(10): addingInsertsNewestFirst, countCapEvictsOldest, entriesOlderThan30DaysArePruned,
exactly30DayOldEntrySurvives, prunedAppliesCapAndAgeAtLoad, removingReturnsEntry, removingUnknownIDIsNoOp,
prunedOfMissingFilesDropsOnlyMissing, jsonRoundTrip, corruptJSONThrows.
HistoryStore(10): addScreenshotWritesCopyThumbAndIndex, addRecordingStoresReferenceNotCopy,
reloadRoundTripsIndex, capEvictionDeletesOwnedFiles, removeNeverDeletesSavedRecordingFile,
clearAllEmptiesIndexAndDeletesOwnedFiles, corruptIndexStartsEmpty, missingRecordingFilePrunedAtLoad,
agePruneAppliesAtLoad, savedFileExistsReflectsDisk.
RestoreStack(4): popReturnsNewestFirst, isEmptyTracksContents, depthCapDropsOldest, repushMovesIDToTop.
ThumbnailRenderer(4): capsLongestSideAt400, smallImagesNotUpscaled, outputIsJPEG, garbageDataReturnsNil.

## History window UI (App layer, not this module)
Grid of thumbnails; kind badge (camera/film glyph); relative date ("2h ago"); action bar:
Copy, Annotate (screenshots), Pin (screenshots), Show in Explorer, Delete; double-click = annotate/open player.
