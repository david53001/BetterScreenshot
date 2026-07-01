# Port Reference — OverlayKit (ground truth for the C#/.NET port)

Source = Swift `Packages/OverlayKit`. Target namespace `BetterScreenshot.Overlay`.
Covers: area-selection overlay, Quick Access thumbnail + 3-item stack, Pin-to-screen panels, HUD toast, window picker.
NSPanel → WPF borderless `Window` (`WindowStyle=None`, `AllowsTransparency=True`, `Topmost=True`, `ShowInTaskbar=False`, `ShowActivated=False`).
**Windows uses top-left screen coords throughout — drop all the Cocoa Y-flips.**

## Types (→ C# classes)
- `SelectionResult { Rect globalRect(top-left px); string monitorDeviceName }`.
- `QuickAccessActions { onCopy, onSave, onAnnotate, onPin, onOpen, onReveal; Func<string?> fileForDrag }`.
- `QuickAccessKind { Screenshot, Recording }`.
- `DismissReason { Closed, Evicted, ActionTaken }` — only Closed/Evicted are restorable.
- `SelectionOverlayController.present(cb: SelectionResult?)` / `cancel()`.
- `QuickAccessOverlayController { onDismissed(DismissReason); present(image, origin, kind, actions); dismiss(reason); move(origin) }`.
- `QuickAccessStackController { maxCount=3; present(image, kind, actions, onDismissed, originForIndex:Func<int,Point>) }`.
- `PinStyle { double cornerRadius; bool shadow }`, `PinActions { onCopy, onSave }`, `PinPanelController.pin(image, pixelSize, sourceRect?, screen, style, actions)`.
- `PinGeometry.initialFrame(...)` / `zoomedFrame(...)` — PURE, unit-tested (see below).
- `HUDController.show(message, screen)`.
- `WindowPickerController { present(hitTest:Func<Point,(uint id,Rect frame,string? title)?>, onPicked:Action<uint?>); cancel() }`.
- `DraggableImageView` → WPF drag-source behavior: exports a file (temp PNG for screenshots, real file for recordings).

## Area-selection overlay — exact UX
- One full-screen borderless window PER monitor (topmost, above everything).
- Whole screen dimmed **black @ 0.35**. Cursor = **crosshair**.
- Drag to draw selection: **white 1px outline** rect. Live **"W × H"** integer-pixel label, **12pt medium white**, 4px above selection top; if it would clip off top, place 4px *inside* the top edge.
- Commit on mouse-up (min **1×1** px, smaller = cancel) → fire completion with global rect + monitor id. **First monitor to complete wins** (singleton guard).
- **Esc** cancels. Re-invoking capture while active cancels the open selection (no stacking).
- No magnifier/loupe (out of scope). No Enter-to-commit.

## Quick Access thumbnail panel
- Size **220×168**. Corner radius **12**. Has shadow. Floating/topmost, non-activating, appears over fullscreen apps.
- Background: screenshot = window bg; recording = **blue-tinted** (systemBlue blended 0.85 with window bg).
- Thumbnail **200×112** at inset (10,46 from bottom-left → top-left equivalent), corner radius **6**, aspect-fit, drag-to-export.
- Button row: height **30**, button width **36**, spacing **6**, y-offset **8**.
- **Screenshot buttons:** Copy (`doc.on.doc`, keeps open) · Edit (`pencil.tip.crop.circle`, dismiss actionTaken) · Pin (`pin`, actionTaken) · Save (`square.and.arrow.down`, actionTaken) · Close (`xmark`, **Closed**).
- **Recording buttons:** Copy file (`doc.on.doc`, keeps open) · Open (`play.fill`, actionTaken) · Show in folder (`folder`, actionTaken) · Close (`xmark`, Closed).
- **No auto-dismiss** — persistent until user action.
- Drag: screenshot drags a temp PNG (deleted **300s** after drag); recording drags the real saved file (not deleted).

## Stack (QuickAccessStackController)
- Max **3**. New capture inserts at index 0 (topmost). If full, oldest is `dismiss(.evicted)`.
- `restack()` repositions all via `originForIndex(i)` → `move()`. Newest presented last = top z-order.
- `originForIndex` supplied by App (default bottom-right corner, margin **24**, step ~180 between slots).
- Each overlay's onDismissed removes it + restacks.

## Pin panels + PinGeometry (PURE — unit-tested)
- `initialFrame(imagePixelSize, backingScale/dpiScale, visibleFrame, sourceRect?, maxFraction=0.8)`:
  - point/logical size = pixelSize / dpiScale. Clamp to ≤80% of visible frame (aspect preserved). Center on sourceRect if given, else center of visible frame. Stay fully inside visible frame.
- `zoomedFrame(current, naturalSize, factor, minScale=0.25, maxScale=3.0)`: scale about center, clamp scale to [0.25,3.0].
- Pin panel interactions: drag to move; bottom-right 16px hotspot or scroll to resize (scroll factor `1+deltaY*0.005`, min accept 0.05); double-click = copy; right-click menu (copy/save/close). Min width **40**. Close button `xmark.circle.fill` on hover.

## HUD toast
- Bottom-center pill, dark vibrant bg, **13pt medium** white text, padding 18×10, corner radius = height/2, y = bottom+80. Auto-dismiss **1.5s**.

## Window picker overlay
- Per-monitor full-screen. Dim **black @ 0.15**. Hovered window: fill **accent @ 0.18**, stroke **accent 3px**, title caption (**13pt semibold** white on **black @ 0.6**, pad 6, radius 6). Click picks; Esc cancels.

## Constants (quick table)
QA panel 220×168 · radius 12 · thumb 200×112 radius 6 · btn 36w row 30h spacing 6 · stack max 3 margin 24 ·
dim 0.35 (sel) / 0.15 (picker) · sel outline white 1px · dims label 12pt med · HUD 13pt 1.5s ·
picker highlight accent 0.18 / stroke 3px · pin max 80% / zoom 0.25–3.0 / resize hotspot 16 / min 40 · drag temp cleanup 300s.

## Tests to re-create (PinGeometry — 9)
retinaImageGetsPointSize (400x200 @2 → 200x100), centersOnVisibleFrameWithoutSource, centersOnSourceRect,
clampsTo80PercentOfScreen (4000x2000 on 1000x800 → 800x400), staysInsideVisibleFrame, zoomScalesAroundCenter,
zoomClampsToMinAndMax (→0.25/3.0), nonZeroOriginVisibleFrameStillContains, clampsHeightLimitedImages.

## Icons used (author natively — see icons.md)
doc.on.doc, pencil.tip.crop.circle, pin, square.and.arrow.down, xmark, xmark.circle.fill, play.fill, folder.
