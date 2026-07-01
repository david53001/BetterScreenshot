# Port Reference — Icon & Glyph Inventory (ALL hand-authored, no screenshots)

Hard requirement (owner): **every icon is created by us as native vector art.** No screenshots, no cropped
CleanShot/BetterScreenshot images, no copied SF Symbol image files. We hand-author each glyph as WPF `Geometry`
(Path `Data`) in a shared `ResourceDictionary` (`Resources/Icons.xaml`), sized on a 24×24 viewbox, filled with
`currentColor` semantics (bind Fill to a brush). These are original path drawings that merely *resemble* the
same universally-recognizable symbols (a gear, a trash can, an arrow) — which is fine; we author the vectors.

Consumption: a small `<Path>`-based `IconPresenter` control takes an icon key + brush + size.

## Complete glyph list (SF Symbol name on mac → our icon key → shape to draw)
| mac SF Symbol | our key | shape |
|---|---|---|
| camera.viewfinder | `camera-viewfinder` | camera body + corner viewfinder ticks |
| stop.circle.fill | `stop-circle` | filled circle w/ rounded square knockout |
| record.circle | `record-circle` | ring + filled center dot |
| checkmark.circle.fill | `check-circle` | filled circle + check |
| camera | `camera` | camera body + lens |
| film | `film` | film strip rectangle + sprocket holes |
| photo | `photo` | picture frame + mountain + sun |
| exclamationmark.triangle | `warning` | triangle + ! |
| gearshape | `gear` | cog wheel |
| keyboard | `keyboard` | rounded rect + key dots |
| xmark | `close` | X strokes |
| xmark.circle.fill | `close-circle` | filled circle + X knockout |
| mic | `mic` | capsule + stand |
| speaker.wave.2 | `speaker` | speaker + 2 waves |
| video | `video` | camcorder body + play triangle |
| doc.on.doc | `copy` | two offset document rects |
| pencil.tip.crop.circle | `edit` | circle + pencil tip |
| pin | `pin` | push-pin |
| square.and.arrow.down | `save` | tray + down arrow |
| play.fill | `play` | filled triangle |
| folder | `folder` | folder shape |
| cursorarrow | `cursor` | arrow pointer |
| arrow.up.right | `arrow` | diagonal arrow (this is the annotation-arrow tool glyph) |
| line.diagonal | `line` | diagonal line |
| rectangle | `rect` | rounded rectangle outline |
| rectangle.fill | `rect-fill` | filled rounded rectangle |
| circle | `ellipse` | circle outline |
| textformat | `text` | "A" / text-format mark |
| 1.circle.fill | `counter` | filled circle + "1" |
| drop.fill | `blur` | teardrop (blur) |
| square.grid.3x3.fill | `pixelate` | 3×3 grid of squares |
| crop | `crop` | crop corners |
| square.stack | `stack` | stacked squares |
| square.3.layers.3d.top.filled | `bring-front` | layered squares, top emphasized |
| square.3.layers.3d.bottom.filled | `send-back` | layered squares, bottom emphasized |
| trash | `trash` | trash can |
| arrow.uturn.backward | `undo` | u-turn arrow left |
| arrow.uturn.forward | `redo` | u-turn arrow right |

~38 glyphs. All simple enough to author by hand as path data.

## App icon (multi-size .ico, authored from scratch)
Reproduce the mac look (tools/make-icon.swift): charcoal squircle background **#1C1C1C**, centered white camera
glyph — rounded body ~60%×40% of canvas, circular lens ~27% diameter, small viewfinder hump on top, tiny flash
window. Render our own vector at 16/32/48/64/128/256 and pack into `Resources/AppIcon.ico`. Also used as the
tray icon base (monochrome camera-viewfinder variant for the tray).

## Notes
- Keep stroke widths visually consistent (≈1.5–2 units on the 24 grid for outline glyphs).
- Tool glyphs in the editor toolbar render at 16pt; tray at 16–20px; onboarding check at ~50px — all vector, crisp at any DPI.
