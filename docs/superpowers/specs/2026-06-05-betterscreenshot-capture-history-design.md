# BetterScreenshot v2.3 — Capture History + Restore Recently Closed

Date: 2026-06-05 · Status: **designed — awaiting plan**
Builds on: v2.2 (`main`, commit 28403d2+) · Ends at tag: `v2.3-history`

> **For a fresh session:** read `CLAUDE.md` first. Then turn this spec into a plan with the
> `superpowers:writing-plans` skill and execute it with `superpowers:subagent-driven-development`.
> Verify integration-point symbols against the live code before writing the plan — file/line
> references were accurate as of v2.2.

## Goal

Clone CleanShot's Capture History (spec §6): every capture and recording is remembered locally
and browsable from the menu bar, and an accidentally-dismissed Quick Access overlay can be
brought back. Solves the recurring "I dismissed it before saving" and "where did yesterday's
screenshot go" pains.

1. **Capture History** — every screenshot (all after-capture modes, including copy-only) and
   every finished recording lands in a local, capped, prunable history. Browsable grid window
   with per-item actions.
2. **Restore Recently Closed** — re-present the most recently ✕-closed or evicted Quick Access
   overlay (menu item + bindable hotkey, default unbound).

## Out of scope

Cloud anything (hard constraint) · history for editor exports/annotated copies (the original
capture is already in history) · Quick Look previews · search/filtering · iCloud/Time Machine
exclusion flags · per-item tags or favorites · history for pins · migrating pre-v2.3 captures.

## UX flows

### Capturing (no new user steps)
Every successful capture/recording is added to history automatically — including copy-only
screenshots that today vanish when the clipboard changes. No HUD/feedback (silent bookkeeping).

### History window — menu item "History…", bindable hotkey `openHistory` (default unbound)
- A normal titled window (like Settings, not a floating panel), ~700×500, resizable.
- Grid of thumbnails, newest first; each cell shows thumbnail, kind badge (camera / film SF
  symbol), and relative date ("2h ago").
- Selection + action bar (and right-click menu) per item:
  - **Copy** — image to clipboard (screenshots) / file URL (recordings); "Copied" HUD.
  - **Annotate** — screenshots only; opens the existing editor with the stored full-res image.
  - **Pin** — screenshots only; existing pin flow, centered on main screen.
  - **Show in Finder** — recordings and any item whose file still exists on disk.
  - **Delete** — removes entry + history-owned files (never deletes a recording's saved file).
- Double-click: screenshots → Annotate; recordings → open in default player.
- Recordings whose saved file was deleted by the user show a "file missing" badge; pruned on
  next launch.
- Empty state: "No captures yet" placeholder text.

### Restore Recently Closed — menu item, bindable hotkey `restoreRecentlyClosed` (default unbound)
- Re-presents the newest entry from a small LIFO of overlays that were **✕-closed or evicted**
  (deliberate actions — save, annotate, pin, drag-out — don't count as "accidentally closed").
- Restored overlay is a fresh Quick Access card wired with the standard actions, built from the
  history entry's full-res image (screenshots) or file URL (recordings).
- Menu item disabled when the LIFO is empty. LIFO depth 5, in-memory only (cleared on quit).

### Settings (General tab, new "History" section)
- **Keep capture history** toggle (default **on**). Turning it off stops recording new entries
  (existing entries remain until cleared).
- **Keep last** picker: 10 / 50 (default) / 200 items.
- **Clear History…** button with confirmation alert; deletes the entire history directory.
- Disk note shown as caption: full-resolution screenshot copies can be several MB each.

## Storage

- Directory: `~/Library/Application Support/BetterScreenshot/History/`.
- `history.json` — Codable index, written atomically. Entry fields: `id: UUID`,
  `kind: .screenshot|.recording`, `date: Date`, `imageFile: String?` (history-owned full-res
  PNG, screenshots only), `filePath: String?` (absolute path to the user's saved file,
  recordings only), `thumbFile: String` (history-owned ~400 pt JPEG).
- Screenshots: history stores **its own full-res PNG copy** (copy-only captures have no other
  file). Recordings: history stores **a reference** to the already-saved file plus a thumbnail
  (no video duplication).
- Retention (applied on every add and on load): count cap (settings) **and** 30-day age prune —
  mirrors CleanShot's "~1 month". Evicted/pruned entries delete their history-owned files.
- Privacy: the directory inherits `~/Library` user-only permissions; screenshots may contain
  sensitive content, hence the off toggle + Clear History affordances.

## Architecture

New local package **HistoryKit** (zero coupling: imports Foundation/CoreGraphics/ImageIO only —
no other kit, matching the architecture's kit-independence invariant). App composes, as always.

### HistoryKit (TestKit test target, mirroring CaptureKit's manifest)
- `HistoryEntry.swift` — the Codable entry value type above + `HistoryKind`.
- `HistoryIndex.swift` — **pure**: ordered entries; `adding(_:cap:now:)` (insert newest-first,
  apply count cap + 30-day prune, return evicted entries so the store can delete files),
  `removing(id:)`, `prunedOfMissingFiles(exists: (String) -> Bool)`, JSON round-trip. TDD.
- `HistoryStore.swift` — file IO on top of the index: create dir, save PNG copy + JPEG thumb
  (downscale via ImageIO `CGImageSourceCreateThumbnailAtIndex`), atomic `history.json` writes,
  `clearAll()`. Thin; probe-style TestKit tests against a temp directory (like
  `TempImageWriterTests`).
- `ThumbnailRenderer.swift` — pure-ish: CGImage → ≤400 pt JPEG data. Tested headless.

### OverlayKit
- `QuickAccessOverlayController` — `dismiss()` gains a reason so restore only tracks accidental
  closes: `enum DismissReason { case closed, evicted, actionTaken }`; `onDismissed` becomes
  `((DismissReason) -> Void)?`. ✕ and eviction pass `.closed`/`.evicted`; save/annotate/pin/
  drag-out pass `.actionTaken`. `QuickAccessStackController` forwards the reason.

### App
- `HistoryWindowController` + `HistoryView` (SwiftUI `LazyVGrid` hosted via
  `NSHostingController`, mirroring the Settings window pattern). Manual GUI verification per
  project norm.
- `CaptureCoordinator.handle(_:sourceRect:)` — add screenshot to history before dispatching the
  after-capture action (guarded by the settings toggle). Track ✕-closed overlays into the
  restore LIFO via the new dismiss reason.
- `RecordingCoordinator.stop()` — add recording entry (file path + thumbnail; the thumbnail
  helper already exists as `Self.thumbnail(for:)`) after a successful save, both MP4 and GIF
  paths.
- `SettingsStore` — `historyEnabled: Bool`, `historyCap: Int` persisted via the existing
  string-dictionary pattern in `CaptureSettings` (round-trip tested in CaptureKit).
- `HotkeyAction` (CaptureKit) — new cases `openHistory`, `restoreRecentlyClosed`, both
  `defaultCombo == nil` (unbound; bindable in the Shortcuts tab — the unbound flow already
  exists since v1.4).
- `MenuBarController` — "History…" and "Restore Recently Closed" items (+ validation).

## Error handling

- History write failures (disk full, permissions) → log via NSLog and skip silently; never
  block or fail the capture flow itself.
- Corrupt/unreadable `history.json` → start with an empty index (log), don't crash; orphaned
  image files in the directory are ignored.
- Deleting a recording entry never deletes the user's saved recording file.

## Testing

- **TestKit (automated)**: `HistoryIndex` add/cap/prune/evict/missing-file rules + JSON
  round-trip; `ThumbnailRenderer` output size; `HistoryStore` temp-dir round-trip (save → load
  → clear); `CaptureSettings` round-trip with the two new keys; `HotkeyAction` table includes
  the two new unbound actions.
- **Manual checklist (GUI)**: copy-only capture appears in history; recording appears with
  working Show in Finder; cap eviction at 10 (set low for the test); Clear History empties the
  window and the directory; Restore Recently Closed brings back a ✕-closed overlay but not a
  saved one; toggle off stops new entries; annotate-from-history opens the editor; missing-file
  badge after deleting a recording in Finder; window resize/grid reflow; dark mode.

## Build order (one plan)

1. HistoryKit scaffold + `HistoryIndex` (TDD, pure) → 2. `ThumbnailRenderer` + `HistoryStore`
(TDD, temp-dir probes) → 3. `CaptureSettings`/`HotkeyAction` additions (TDD) → 4. Dismiss-reason
plumbing in OverlayKit → 5. Coordinator hooks (capture + recording add; restore LIFO) →
6. History window UI + menu items + settings section → 7. Manual checklist, CHANGELOG, README,
bump 2.3.0, tag `v2.3-history`.

## Risks / probes for the implementing session

- `CGImageSourceCreateThumbnailAtIndex` downscale quality/orientation on headless CLT — probe in
  the first store task (expected fine; ImageIO is already used by `ImageEncoder`).
- Disk growth: 200-item cap of 5K-display PNGs can reach a few GB — the settings caption and
  50-item default mitigate; do not silently raise the default.
- The history add for screenshots passes the full-res `CGImage` across the PNG encode path —
  reuse `ImageEncoder.encode(_:as:.png)`, don't re-implement.
