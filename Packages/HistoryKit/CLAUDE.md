# HistoryKit — capture history (pure logic + file IO)

The capture-history index/store, restore stack, and thumbnail rendering. Pure logic + file IO, no UI.
Imported by the `App/` target (`App/History`).

## Key files (`Sources/HistoryKit/`)
- `HistoryEntry.swift` — one history record.
- `HistoryIndex.swift` — the in-memory/on-disk index.
- `HistoryStore.swift` — store + file IO (copies, thumbnails, pruning).
- `RestoreStack.swift` — undo/restore stack (newest-first).
- `ThumbnailRenderer.swift` — thumbnail generation (caps longest side).

## Invariants (covered by tests)
- Saved **recordings are stored by reference and never copied or deleted** by the store; **screenshots
  are copied + thumbnailed** and their owned files ARE evicted on cap/age pruning.
- A corrupt index loads as empty; missing recording files are pruned at load; age/cap pruning applies
  at load.

## Verify
`swift run --package-path Packages/HistoryKit HistoryKitTests`.
