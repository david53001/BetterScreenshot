# RecordingKit — screen recording engine + overlays

Screen recording (ScreenCaptureKit), GIF export, and the on-screen recording overlays. Imported by the
`App/` target (`App/Recording`).

## Key files (`Sources/RecordingKit/`)
- `ScreenRecorder.swift` — the recording engine.
- `RecorderState.swift`, `RecordingConfig.swift` — recording state machine + config (pure, tested).
- `GIFExporter.swift`, `GIFTiming.swift` — GIF output + frame timing.
- `MicCapturer.swift` — microphone audio.
- `CameraBubbleController.swift`, `KeystrokeOverlayController.swift`, `ClickHighlighter.swift` —
  camera bubble + keystroke/click visualizers shown during recording.

`RecorderState` and `RecordingConfig` are unit-tested; the AV/overlay pieces are verified manually.

## Verify
`swift run --package-path Packages/RecordingKit RecordingKitTests`.
