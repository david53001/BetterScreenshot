# App/History — capture history

- `HistoryService.swift` — app-side glue over `Packages/HistoryKit`: records captures/recordings into
  the history store and exposes them to the rest of the app.
- `HistoryWindowController.swift` — the history browser window (lists past captures, restore/reveal).

Index/store/restore-stack/thumbnail logic (pure + file IO) lives in `Packages/HistoryKit` and is
unit-tested there. Invariant inherited from HistoryKit: saved **recordings are referenced, never
copied or deleted**; screenshots are copied + thumbnailed; age/cap pruning happens at load. Verify via
HistoryKit tests plus opening the history window in the built app.
