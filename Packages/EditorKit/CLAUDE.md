# EditorKit — annotation editor (model + canvas + renderer)

The annotation document model, a custom AppKit `NSView` canvas + tools, and the flatten-to-image
renderer. Imported by the `App/` target (capture flow opens the editor).

## Key files (`Sources/EditorKit/`)
- `EditorDocument.swift` — the annotation document model.
- Annotation types: `Annotation.swift`, `ArrowAnnotation.swift`, `ShapeAnnotations.swift`,
  `TextAnnotation.swift`, `CounterAnnotation.swift`, `RedactionAnnotations.swift`.
- Styling: `AnnotationStyle.swift`, `RGBAColor.swift` (Codable — persisted as the app's sticky default).
- UI: `EditorWindowController.swift`, `EditorCanvasView.swift`, `EditorChrome.swift`, `EditorTool.swift`.
- Rendering/geometry: `DocumentRenderer.swift`, `Redactor.swift`, `ArrowGeometry.swift`.

## Invariants (do not break)
- Annotations live in **base-image pixel space, top-left origin**.
- The renderer draws into a **flipped `NSGraphicsContext`** so AppKit drawing (incl. text) is
  right-side-up. Changing the flip will mirror/upside-down everything.
- **Sticky default style:** the app injects a `defaultStyle` (last-used color/size) and listens for
  style changes; the persistence itself lives in `App/Settings/SettingsStore` (`editorDefaultStyle`).
- The bottom-bar **Stack** button is wired in the app to `keepInStack` (add to Quick Access), not Pin.

## Verify
`swift run --package-path Packages/EditorKit EditorKitTests`.
