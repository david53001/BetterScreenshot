# Quick Access Card Redesign — Process Log

> **Date:** 2026-07-03 · **Branch:** `windows-port` · **Commit:** `e37954a`
> **Scope:** the Windows (.NET 9 / WPF) port only. The macOS Swift app is the behavioral source of
> truth and was left untouched.
>
> This is a retrospective of *how* the change was made — the request, the exploration, the design
> decisions (with the alternatives rejected and why), the implementation, and how it was verified.
> Written to be readable with zero prior context.

---

## 1. The request

The owner pointed at a live capture's Quick Access thumbnail and asked (paraphrased from their words):

> "I want the image to be the full thing — it should be rounded, just the full block — and the UI
> should overlay above it and **contrast to the image automatically**. If the image is white, the
> button should be black. On hover too — detect automatically for every color palette and contrast it."

Three concrete asks, in order of importance:

1. **Full-bleed image.** The card *is* the screenshot — the whole block, rounded corners.
2. **Overlaid controls.** The action buttons float on top of the image, not in a separate strip.
3. **Automatic contrast.** Glyphs (and their hover/press states) flip light/dark to stay legible
   against whatever the image shows behind them.

---

## 2. Starting point (what the card was)

`Overlays/QuickAccessWindow.xaml` was a **fixed 220×184** window: a dark rounded `Border` (`Theme.CardBrush`
`#0E0E0E`) with 10px padding, holding a `DockPanel`:

- **Bottom band:** a `StackPanel` of icon buttons (`Theme.SubtleButton` — transparent with a fixed
  translucent-*white* hover pill, fixed near-white glyphs `#F2F2F5`).
- **Fill:** the screenshot as a **letterboxed** `Image` (`Stretch="Uniform"`) inside a faint `#14FFFFFF`
  rounded panel.

So the image was a small preview in the top portion and the buttons lived on their own dark strip below —
the opposite of "the image is the full block." Contrast was fixed (always white-on-dark), which is exactly
what breaks over a bright screenshot.

Positioning was handled by `QuickAccessStackController` using `OverlayPositioner.StackedOrigin`, which
assumes **uniform** card size (`CardWidth=220`, `CardHeight=184`) and offsets each card by a fixed step.

---

## 3. How I explored (before writing anything)

Read, in rough order, to build a correct mental model rather than guess:

- The referenced temp file `…\quickaccess.png` — confirmed it is the **drag-export temp copy of the actual
  screenshot** (written by `CaptureCoordinator.ShowOverlayCard` via `ImageIo.WriteTempPng`), i.e. real image
  content, not a UI mockup.
- `QuickAccessWindow.xaml` / `.xaml.cs` — current layout + how buttons are built (`MakeButton`, a shared
  `Style`, `IconPresenter` glyphs) and how drag-to-export is wired (mouse handlers on the `Thumb` image).
- `QuickAccessStackController.cs`, `QuickAccessTypes.cs` — stacking, eviction (max 3), dismiss/restack.
- `Capture/OverlayPositioner.cs` + `OverlayPositionerTests.cs` — the pure stacking math and its tests.
- `Resources/Theme.xaml`, `Controls/IconPresenter.cs`, `App.xaml` — the monochrome theme tokens, the glyph
  renderer, and confirmation that `Icons.xaml` + `Theme.xaml` are merged app-wide.
- `Capture/CaptureCoordinator.cs` (around `ShowOverlayCard`) — **the key finding: the card is handed the
  full-resolution `BitmapSource`**, so I can sample its pixels directly to drive contrast.
- `Platform/ThumbnailRenderer.cs` — the codebase's existing `TransformedBitmap`/scale pattern, to match style.
- `UiPreview.cs`, `scripts/publish-app.ps1`, the test `.csproj` — how the app is previewed, deployed, tested.

**Decisive takeaways:** (a) the real screenshot is available for luminance sampling; (b) going full-bleed +
aspect-fit means cards get **variable heights**, which the fixed-step stacker can't do — so the controller
needed reworking too.

---

## 4. Design decisions (and the alternatives rejected)

### 4.1 Full-bleed sizing: aspect-fit, not crop-to-fixed
- **Chosen:** fix the card **width** (236 DIP) and derive **height** from the image's aspect ratio,
  clamped to `[132, 280]`. In the common case the block matches the image aspect exactly, so the whole
  capture is visible *and* fills the block with no letterbox. Extreme panoramas/portraits clamp and crop
  minimally via `UniformToFill`.
- **Rejected:** keep the fixed 220×184 window and `UniformToFill`-crop. Simpler (stacking unchanged) but it
  *hides part of the screenshot* — directly contradicting "the image should be the full thing."
- **Consequence accepted:** variable heights → rework the stack positioner (see 4.6).

### 4.2 Rounded corners that also clip the overlays
A WPF `Border`'s `CornerRadius` rounds its own background/border but **does not clip its children** — a
square button strip or scrim would poke out past the rounded corners. Solutions weighed: `OpacityMask`
(heavy), `ClipToBounds` (rectangular only, doesn't round).
- **Chosen:** clip the content `Grid` (`Root`) with a `RectangleGeometry` (radius 14), (re)applied on
  `SizeChanged` so it always matches actual size. The **drop shadow is generated from that rounded, clipped
  content**, so it hugs the card's rounded silhouette; a 1px hairline `Border` is drawn on top for a crisp edge.

### 4.3 Auto-contrast: one coherent toolbar tone from a luminance sample
- **Sampling:** crop the image's bottom ~30% strip (where the toolbar sits) → downscale to ≤48px →
  convert to BGRA → average **Rec. 709 relative luminance** (`0.2126R + 0.7152G + 0.0722B`).
- **Decision:** `luminance > 0.58` ⇒ *light background* ⇒ dark controls; else light controls.
- **Chosen one tone for the whole row**, not per-button. A single decision reads as intentional design;
  per-button colors (some black, some white glyphs side by side over a gradient) would look like a bug.
- The **glyph, hover pill, pressed pill, and scrim all derive from the same boolean**, so hover/press
  contrast is automatic — satisfying "on hover too."

### 4.4 The scrim — the one real judgment call
Pure glyph-only contrast fails where the bottom edge is *mixed* (half light, half dark): the average is
mid-grey and neither pure-black nor pure-white glyphs pop everywhere.
- **Chosen:** a subtle bottom gradient scrim that **shares the image's tone** (faint *white* over a light
  image, faint *black* over a dark one, max ~55% alpha, fading to transparent over the bottom ~40% of the
  card). This guarantees the opposite-tone glyph always separates, without ever looking like a heavy dark
  bar on a white image — it adapts with the rest.
- **Rejected:** glyphs only (unreliable over photos) and a permanent dark scrim (looks wrong on light
  images, and is what the owner was moving away from).
- Flagged to the owner as the single judgment call; trivially removable if they want glyphs-only.

### 4.5 Adaptive hover via `DynamicResource`
WPF `Trigger`s reference brushes statically, so a per-card hover color needs indirection.
- **Chosen:** the local `QA.IconButton` template references `{DynamicResource QA.HoverBrush}` /
  `{DynamicResource QA.PressedBrush}`; the code-behind swaps those entries in the window's `Resources` per
  card. `DynamicResource` re-resolves on the swap.
- **Rejected:** building the whole `ControlTemplate` in code per button (verbose, harder to read).

### 4.6 Variable-height stacking in the controller
- **Chosen:** `QuickAccessStackController.Restack` now walks the cards and positions each **cumulatively**
  from the corner using its **actual `Width`/`Height`** (bottom corners stack upward, top corners downward;
  newest sits closest to the corner).
- `OverlayPositioner.StackedOrigin` (the fixed-step pure fn) is **left intact with its tests** — it's just
  no longer the path Quick Access uses.

### 4.7 Testability split
- **Chosen:** put the *pure* math — `AverageLuminance(byte[], stride, w, h)` and
  `IsLightBackground(double)` — in a `public static QuickAccessContrast` with no WPF window dependency, so
  the core decision is unit-tested deterministically. The WPF glue (crop/downscale/convert + brush
  construction) lives in an `internal ContrastPalette` on top of it.

---

## 5. Implementation

| File | Change |
|------|--------|
| `Overlays/QuickAccessContrast.cs` **(new)** | `QuickAccessContrast` (pure luminance + threshold) and `ContrastPalette` (samples the image bottom strip; yields glyph / hover / pressed / scrim brushes from one light/dark decision). |
| `Overlays/QuickAccessWindow.xaml` | Full-bleed `Image` (`UniformToFill`) in a rounded-clipped `Root` grid; transparent drag surface; adaptive bottom `Scrim`; overlaid `ButtonRow`; local `QA.IconButton` style + `QA.HoverBrush`/`QA.PressedBrush` resources; hairline + rounded drop shadow. |
| `Overlays/QuickAccessWindow.xaml.cs` | Size the card to the image aspect (clamped); set the rounded clip (and keep it in sync on `SizeChanged`); apply the `ContrastPalette` (scrim fill + hover/pressed resources + per-glyph brush); drag moved to the dedicated `DragSurface`. |
| `Overlays/QuickAccessStackController.cs` | Cumulative, actual-size stacking from the corner (replaces the fixed-step `StackedOrigin` call). |
| `tests/…/QuickAccessContrastTests.cs` **(new)** | 8 tests: white→light, black→dark, half/half→mid/dark, stride padding respected, threshold boundary, empty buffer. |
| `docs/PROGRESS.md` | Ledger entry. |

**Coordinate/units note:** card sizes and `SystemParameters.WorkArea` are both DIPs, so stacking math is
consistent; the luminance sample works in device pixels on the source `BitmapSource`.

---

## 6. Verification (how I actually confirmed it, without a display)

1. **Compile:** `dotnet build` the App → **0 warnings / 0 errors**. (First pass surfaced a `Brush`
   ambiguity — the App enables WinForms, so `System.Drawing.Brush` is an implicit global using; fixed with a
   `using Brush = System.Windows.Media.Brush;` alias.)
2. **Unit tests:** `dotnet test` → **250 passed / 0 failed** (the 8 new luminance/threshold tests included,
   and the untouched `OverlayPositioner` tests still green).
3. **Actually *seeing* it — offscreen render harness.** Since I can't view the running window, I wrote a
   throwaway WPF exe in the scratchpad (`qarender/`) that references the built App, spins up an
   `Application` with the merged `Icons.xaml` + `Theme.xaml`, constructs a real `QuickAccessWindow` with
   **white / dark / wide-gradient** sample images, `Measure`/`Arrange`es the content, and
   `RenderTargetBitmap`s it to PNG. The renders confirmed: **black glyphs on the white image**, **white
   glyphs on the dark and gradient images**, correct full-bleed rounding + shadow, and aspect-correct card
   sizes. This was the real "does it look right" check.
4. **Deploy:** the tray agent locks its binaries, so I stopped the running process, ran
   `publish-app.ps1 -NoShortcut` to rebuild `dist/`, and **relaunched** the same exe — per the project norm
   that a plain build doesn't update the `dist/` agent the owner runs.
5. **Commit** on `windows-port` (`e37954a`); not pushed (per the git norm — commit freely, never push).

---

## 7. Assumptions & judgment calls (owner was away)

- **Kept the subtle tone-matched scrim** as the legibility guarantee (§4.4) — the one aesthetic call.
- **One toolbar tone**, not per-button (§4.3).
- **Card width 236 DIP; height clamp 132–280; light/dark threshold 0.58** — reasonable defaults, easily tuned.
- **Windows-only**; the macOS app is the source of truth and isn't verifiable here.

## 8. Not verified here / possible follow-ups

- **Live hover** feedback and the look against a **real desktop wallpaper** behind an actual capture — only
  static renders were checked.
- **Sampling cost on very large (4K/8K) captures** — mitigated by cropping then downscaling to ≤48px before
  averaging, but not benchmarked.
- If the owner wants **glyphs-only (no scrim)**, that's a one-line change in `ContrastPalette`.
