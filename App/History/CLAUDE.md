# App/History — capture history

- `HistoryService.swift` — app-side glue over `Packages/HistoryKit`: records captures/recordings into
  the history store and exposes them to the rest of the app.
- `HistoryWindowController.swift` — the history browser window (lists past captures, restore/reveal).
- `HistoryItemInteraction.swift` — transparent AppKit layer over each grid cell. Exists because
  SwiftUI on macOS 14 can neither read a click's modifier keys nor start a dragging session with more
  than one file. Selection arithmetic itself is pure and lives in `HistoryKit/HistorySelection.swift`.

Index/store/restore-stack/thumbnail logic (pure + file IO) lives in `Packages/HistoryKit` and is
unit-tested there. Invariant inherited from HistoryKit: saved **recordings are referenced, never
copied or deleted**; screenshots are copied + thumbnailed; age/cap pruning happens at load. Verify via
HistoryKit tests plus opening the history window in the built app.

Dragged files are always the **persistent** ones — the history-owned PNG under
`~/Library/Application Support/BetterScreenshot/History/` for screenshots, the user's saved file for
recordings — never a `$TMPDIR` copy, so the "Keep cached files for" sweep can't delete a file out
from under a drop target.
