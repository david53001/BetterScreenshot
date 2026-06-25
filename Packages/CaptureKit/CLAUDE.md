# CaptureKit — capture engine + pure capture logic

ScreenCaptureKit wrapper plus the pure, TDD'd logic for cropping, encoding, naming, positioning, and
text recognition. Imported by the `App/` target (mainly `App/Capture`).

## Key files (`Sources/CaptureKit/`)
- `CaptureService.swift` — ScreenCaptureKit capture wrapper.
- `CaptureTarget.swift`, `CaptureSettings.swift` — what/how to capture.
- `CaptureGeometry.swift`, `ImageCropper.swift` — geometry + crop math (pure).
- `ImageEncoder.swift` — PNG/JPEG encode; `FileNamer.swift` — output filename rules.
- `OverlayPositioner.swift` — where post-capture overlays sit (pure).
- `TextRecognizer.swift` + `RecognitionResult.swift` — Vision OCR / QR ("Capture Text"); `TempImageWriter.swift`.
- `HotkeyAction.swift`, `HotkeyBindings.swift`, `HotkeyCombo.swift` — the hotkey **model** (binding
  data; registration itself lives in `App/SystemIntegration/HotKeyManager`).

## Conventions / invariants
- Coordinate convention (project-wide): annotations/regions are in base-image pixel space, **top-left
  origin**.
- Pure logic is test-first.

## Verify
`swift run --package-path Packages/CaptureKit CaptureKitTests` (or `scripts/test.sh` for all suites).
