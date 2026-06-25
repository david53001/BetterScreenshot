# App/Capture — screenshot capture orchestration

- `CaptureCoordinator.swift` — drives one capture end to end: area-selection overlay
  (`OverlayKit`) → capture/crop/encode/OCR (`CaptureKit`) → post-capture Quick Access thumbnail
  (`OverlayKit`) → optional annotation editor (`EditorKit`) → output (save / copy / add to History
  via `HistoryKit` / add to the Quick Access stack).

Key collaborators it owns: the Quick Access overlay (`quickAccess`). `keepInStack(...)` adds a
flattened edit to the bottom-right Quick Access stack and History (this is the editor's **Stack**
button target).

Pure capture logic (geometry, crop, encode, filename, OCR) lives in `Packages/CaptureKit` and is
unit-tested there; this file is the app-side orchestration. Verify by running a capture in the built
app.
