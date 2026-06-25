# OverlayKit — selection overlay, Quick Access, pin-to-screen

Floating `NSPanel`/`NSView` UI shown over the desktop: the area-selection overlay, the post-capture
Quick Access thumbnail (and its stack), and pin-to-screen panels. Imported by the `App/` target.

## Key files (`Sources/OverlayKit/`)
- `SelectionOverlayController.swift` + `SelectionResult.swift` — drag-to-select-area overlay.
- `QuickAccessOverlayController.swift` + `QuickAccessStackController.swift` — the bottom-right
  post-capture floating thumbnail and its stack.
- `PinPanelController.swift`, `PinView.swift`, `PinGeometry.swift`, `DraggableImageView.swift` —
  pin-a-screenshot-to-screen panels (Pin action lives on the Quick Access overlay).
- `HUDController.swift` — transient on-screen HUD.

`PinGeometry` is pure and unit-tested; the controllers are AppKit UI verified manually.

## Verify
`swift run --package-path Packages/OverlayKit OverlayKitTests`.
