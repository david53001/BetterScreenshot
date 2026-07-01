# Port Reference — EditorKit (ground truth for the C#/.NET port)

Source = Swift `Packages/EditorKit`. Target namespace `BetterScreenshot.Editor`.
Annotation document model + WPF canvas + tools + flatten renderer. **Annotations live in base-image PIXEL space, top-left origin.**
On WPF, top-left is native — no context flip needed (unlike mac which flips NSGraphicsContext).

## Model
`RGBAColor { double r,g,b,a }` (0–1 sRGB, JSON-Codable).
`AnnotationStyle { RGBAColor strokeColor, fillColor; double lineWidth, fontSize }` (JSON-Codable).
- Default: stroke red **(1, 0.23, 0.19, 1)**, fill = stroke @ 0.25 alpha, lineWidth **4**, fontSize **24**.
`EditorTool { select, arrow, line, rectangle, filledRectangle, ellipse, text, counter, blur, pixelate, crop }`.

`IAnnotation { Guid id; AnnotationStyle style; Rect BoundingBox(); void Draw(ctx); IAnnotation MovedBy(delta) }`.
Default hit-test = **6px slop** around bbox.
Concrete types & fields:
- `ArrowAnnotation { Point start,end }` — shaft (round cap, stops at head base) + filled triangle head; head half-angle **28°**, head length `max(12, lineWidth*3)`.
- `LineAnnotation { Point start,end }`.
- `RectangleAnnotation { Rect frame; bool filled }`, `FilledRectangleAnnotation { Rect frame }`, `EllipseAnnotation { Rect frame }`.
- `TextAnnotation { string text; Point origin(top-left) }` — bold system font, size = style.fontSize, color = strokeColor.
- `CounterAnnotation { int number; Point origin }` — diameter `max(28, fontSize*1.6)`, filled circle + centered white bold text (font = diameter*0.55). `Centered(on, number, style)` factory.
- `PixelateAnnotation { Rect frame; ImagePatch patch }`, `BlurAnnotation { Rect frame; ImagePatch patch }` — patch precomputed, blitted into frame (not live-editable once placed).

`EditorDocument { Image baseImage; IReadOnlyList<IAnnotation> annotations; Size size }` with:
Add, Remove(id), IndexOf(id), Move(id,delta), Replace(id,a), BringToFront(id), SendToBack(id),
TopmostHit(point), IdsIntersecting(rect), NextCounterNumber(), Cropped(rect)→doc (offsets annotations by -rect.origin).
Array order = z-order (first=back, last=front).

## Redactor (blur/pixelate)
- `Pixelate(image, region, blockSize=12)` and `Blur(image, region, radius=12)` → cropped patch or null if region <2×2.
- CoreImage `CIPixellate`/`CIGaussianBlur` → **on Windows** use WriteableBitmap pixel loops (pixelate: average blockSize×blockSize blocks; blur: separable box/Gaussian) or Win2D. Must actually destroy detail (tests check hard-edge reduction).

## Renderer (DocumentRenderer.render(doc, preview?) → Image)
- Allocate RGBA8 surface at base image size; draw base; draw all annotations in order; draw optional in-progress preview on top.
- WPF: `RenderTargetBitmap` + `DrawingVisual`/`DrawingContext`, top-left origin, `BitmapScalingMode.HighQuality`. Text via `FormattedText`. Output PNG/`BitmapSource`.
- Tests require: filled rect renders red at interior pixel; preview drawn on top (not persisted); arrow shaft does NOT bleed past arrowhead tip; base image orientation preserved (no vertical flip).

## Canvas interaction (EditorCanvas)
- Tools: shape tools drag-to-create with live preview, commit on mouse-up. Text = click → inline TextBox, commit on blur/Enter (skip if blank). Counter = click → instant centered badge with next number. Blur/Pixelate/Crop = drag marquee (blue dashed), on release if big enough apply (min blur/pixelate **2×2**, min crop **4×4**).
- Select tool: click selects (empty click deselects); drag moves selection; marquee (blue dashed) selects intersecting; single rect-based selection shows **8 resize handles** (8×8px, ±2px slop), min size 4px; `[`=send back, `]`=bring front; Delete removes.
- Undo/redo: full-document snapshot stacks, max **50**; snapshot on insert/delete/move-drag(if mutated)/resize/z-order/crop. Keys: **Ctrl+Z** undo, **Ctrl+Shift+Z / Ctrl+Y** redo. `canUndo/canRedo`.

## Sticky style defaults + Stack button
- `EditorWindowController(image, defaultStyle=.default)`; callbacks `onCopy(img)`, `onSave(img)`, `onAddToStack(img)`, `onStyleChanged(style)`.
- On open, inject `defaultStyle` into canvas+inspector. `onStyleChanged` fires after color/weight/size change → App persists to settings key `editorDefaultStyle` (JSON).
- **Stack** button (`square.stack`) renders doc → `onAddToStack(img)` → App `keepInStack` (history + Quick Access), closes window. (Pin lives on the Quick Access overlay, not here.)

## Toolbar / inspector layout
- Frosted pill toolbar, 11 tool buttons in 5 groups: [select] [arrow line rectangle filledRectangle ellipse] [text counter] [blur pixelate] [crop]. Button 38×38, symbol 16pt; selected = accent bg + white tint; hover = 13% white.
- Inspector pill (h44), adaptive by tool: color row (8 preset swatches 22×22 + custom color well 28×22) + weight segment S/M/L=**2/4/7** (shape tools) or size segment S/M/L=**18/24/36** (text); select tool = Front/Back/Delete; blur/pixelate = Blur/Pixelate toggle; crop = hint.
- Action bar (h56, hairline top): left = dims label (mono 11.5pt gray); right = Done(Ctrl+W) · Stack(`square.stack`) · Save(`square.and.arrow.down`) · Copy(`doc.on.doc`, accent). Titlebar: Undo(`arrow.uturn.backward`) / Redo(`arrow.uturn.forward`) 26×22.
- Preset swatches (sRGB): Red(1,0.27,0.23) Orange(1,0.62,0.04) Yellow(1,0.84,0.04) Green(0.19,0.82,0.35) Blue(0.04,0.52,1) Purple(0.75,0.35,0.95) White(1,1,1) Black(0,0,0). Selected swatch has white ring 2px.
- Window min **600×440**, max display width **1200**, centering clip for small docs; insets top20 sides24 bottom24.

## Constants table
stroke red(1,.23,.19) · fill α .25 · lineWidth 4 (2/4/7) · fontSize 24 (18/24/36) · arrow head 28° len max(12,lw*3) ·
counter Ø max(28,fs*1.6) text=Ø*0.55 start 1 · hit slop 6 · handle 8 slop 2 · blur r12 · pixelate block12 ·
min crop 4×4 · min redact 2×2 · undo 50 · maxDisplay 1200 · minWindow 600×440.

## Tests to re-create (xUnit) — grouped
EditorDocument(6): addAndCount, topmostHitReturnsLastAdded, moveById, removeAndReorder(bringToFront+remove),
idsIntersectingReturnsOnlyOverlapping, idsIntersectingReturnsAllWhenMarqueeCoversEverything.
DocumentRenderer(4): rendersFilledRectAtTopLeftCoordsInRed, rendersInProgressPreviewOnTop,
arrowShaftDoesNotBleedPastArrowhead, preservesBaseImageOrientation.
ArrowGeometry(3): horizontalArrowheadWings, shaftEndStopsAtArrowheadBase, shaftEndClampsToStartForShortArrow.
CounterAnnotation(3): boundingBoxIsSquareAtOrigin, nextCounterNumberCountsCountersOnly, centeredFactoryCentersBadgeOnPoint.
Redactor(4): pixelatePatchHasRegionSize, blurPatchHasRegionSize, pixelateDestroysDetail, blurDestroysDetail.
TextAnnotation(2): longerStringHasWiderBox, moveOffsetsOrigin.
ShapeAnnotation(3): rectangleBoundingBoxAndMove, ellipseHitTestUsesBoundingBox, lineBoundingBoxSpansEndpoints.
AnnotationStyleCodable(1): annotationStyleRoundTripsThroughJSON.
RGBAColor(2): componentsMatch, defaultStyleIsRed.
Crop(1): cropResizesBaseAndOffsetsAnnotations.

## Icons used (author natively — see icons.md)
Tools: cursorarrow, arrow.up.right, line.diagonal, rectangle, rectangle.fill, circle, textformat, 1.circle.fill, drop.fill, square.grid.3x3.fill, crop.
Actions: square.stack, square.and.arrow.down, doc.on.doc, square.3.layers.3d.top.filled, square.3.layers.3d.bottom.filled, trash, arrow.uturn.backward, arrow.uturn.forward.
