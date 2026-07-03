# Investigation — capture black bar + editor FPS + on-screen "walls" (2026-07-03)

> Process log for three owner-reported issues, written so a zero-context reader can follow the reasoning and
> reproduce the diagnostics. Fix landed in commit `578d891` on `windows-port`. Summary lives in
> [`PROGRESS.md`](PROGRESS.md) (section "Capture black-bar fix + editor FPS + on-screen 'walls'").

## The report

Three issues, all in the WPF Windows port (`windows/`):

1. **Editor "staggering FPS"** — annotating with a tool felt choppy / low-framerate.
2. **Annotations drag out of the image** — you could drag a tool's shape past the image edge; asked for
   "borders that don't let you pass."
3. **Capture goes off the screen** — originally "you can screenshot even off the screen." Mid-session the owner
   clarified with a screenshot: the real symptom is a **"massive black bar on the side"** of the captured image,
   "probably because of the resolution" (owner runs a **stretched resolution**).

Issues 1 and 2 were root-caused by reading the editor code. Issue 3 needed empirical investigation — that's the
bulk of this log.

---

## Issue 3 — the black bar: methodology

### Step 0 — read the evidence, not the label

The owner's screenshot showed the annotation editor displaying a full-screen capture. The right ~27% was **solid
black**. The decisive detail: **the Windows taskbar in the captured image cut off at the content boundary** and did
*not* continue under the black region.

A Windows taskbar always spans the full width of its monitor. So the monitor's real content was only as wide as
where the taskbar ended (~1500 px), and the black was *extra* pixels appended on the right. Conclusion before
touching any code: **the capture requested a wider region than the actual desktop framebuffer, and GDI `BitBlt`
padded the difference with black.**

The capture path (`ScreenCapture.CaptureRegion` → `BitBlt` from `GetDC(NULL)`) sizes a fullscreen grab from
`Screens.Primary().Bounds`, which comes from `GetMonitorInfo`. So the question became: **when does `GetMonitorInfo`
report a width larger than what `BitBlt` can actually read?**

### Step 1 — faithful metrics (`capdiag.ps1`)

A plain PowerShell process is not PerMonitorV2-aware, so its screen metrics would be DPI-virtualized and *not*
match the real app. The diagnostic first calls `SetProcessDpiAwarenessContext(PerMonitorV2)` so every number
mirrors what the app (PMv2 manifest) sees, then dumps monitors, system metrics, the DC's logical-vs-physical
extents, and does a real BitBlt of the primary and scans for a black margin.

Findings:

```
SetProcessDpiAwarenessContext(PMv2) -> ok
SM_CXSCREEN x SM_CYSCREEN     = 1500 x 1080
SM_CXVIRTUALSCREEN x CY       = 3420 x 1080
GetDC(NULL) HORZRES x VERTRES = 1500 x 1080   (logical DC surface)
GetDC(NULL) DESKTOPHORZ x VERT= 1500 x 1080   (physical desktop)
  \\.\DISPLAY1 bounds=(0,0,1500,1080)  size=1500x1080 dpi=96 primary=True
  \\.\DISPLAY2 bounds=(1500,0,3420,1080) size=1920x1080 dpi=96 primary=False
--- capture test: BitBlt primary bounds 1500x1080 ---
  rightmost non-black column  = 1499   (black bar width on right = 0)
```

This reframed everything:

- The rig is **dual-monitor**: primary `DISPLAY1` is **1500×1080** (a stretched resolution on a native-1920
  panel — the owner's "stretched res"); secondary `DISPLAY2` is native **1920×1080** at x-offset 1500.
- Right now, capturing the **primary** is clean (0 px black bar). So the bug is **not reproducible in the current
  config** — it is config/state dependent.
- The width mismatch (1500 vs 1920) between the two monitors was the obvious suspect: something captured a
  1920-wide region while the content was 1500 wide.

### Step 2 — a wrong hypothesis, and how it was killed

Hypothesis: **`GetDC(NULL)` can't read a secondary monitor at a source offset** (a real, commonly-cited GDI
limitation) — so capturing the secondary (`BitBlt` src x=1500) returns black.

`capdiag2.ps1` captured each monitor + the whole virtual desktop and scanned for black. `capsave.ps1` saved the
same as PNGs to look at. The secondary capture came back **almost entirely black** — seemingly confirming the
hypothesis.

But the scan was unreliable: it can't tell a *black-bar artifact* from *genuinely dark screen content*. `capdiff.ps1`
extracted the secondary region from the (working) full-virtual capture and compared it, pixel-mean, against the
offset capture:

```
secondary mean-luma: originRead+crop=0.4  vs  offsetRead=0.4
```

**Identical, and both ~black.** That means the secondary monitor was *genuinely* displaying a black desktop — the
scan proved nothing. Inconclusive, not confirmation.

### Step 3 — the decisive test (`caplive.ps1`)

To disambiguate, put **known-bright content** on the secondary: spawn a white borderless WinForms window covering
`DISPLAY2` (1500,0 → 3420,1080), let it paint, then offset-`BitBlt` that region (exactly the app's path) and
measure luma:

```
WHITE window on secondary -> offset-read secondary mean-luma = 255.0
```

**255.0 = pure white.** Offset-reads onto the secondary monitor work perfectly. The Step-2 hypothesis is **dead** —
there is no multimon offset bug. The earlier "black secondary" was just a black desktop.

### Step 4 — the actual root cause + the fix primitive (`capcaps.ps1`)

Back to Step 0's conclusion: the capture was wider than the framebuffer. The app's only source of size is
`GetMonitorInfo` (`MonitorInfo.Bounds`), which reports the **logical / mode** size. The *real* framebuffer — the
pixels that actually exist to copy — is exposed by the display DC:

```
\\.\DISPLAY1: DESKTOPHORZxVERT = 1500x1080
\\.\DISPLAY2: DESKTOPHORZxVERT = 1920x1080
```

`CreateDC("DISPLAY", deviceName, …)` + `GetDeviceCaps(DESKTOPHORZRES/VERTRES)` gives the true framebuffer per
monitor.

**Root cause:** when a full-screen game or a custom **stretched** resolution leaves the GPU scanout at a size that
Windows' monitor metrics don't reflect, `GetMonitorInfo` reports the wider logical size while the framebuffer (and
thus the readable screen DC) is narrower. `BitBlt` of the reported bounds over-reads past the real desktop and
**pads the excess with black** — the bar. The owner games with stretched resolutions (and prior notes record hitting
capture issues "while a fullscreen game was up"), which is exactly this state.

Why it isn't visible today: in the current session `GetMonitorInfo` (1500) already equals `DESKTOPHORZRES` (1500),
so there's nothing to clamp. The bug needs the transient/stretched state where they diverge.

**Fix (safe in all states):** clamp every display capture to the real framebuffer.
- `Screens.RealFramebufferSize(deviceName)` — `CreateDC` + `GetDeviceCaps(DESKTOPHORZRES/VERTRES)`.
- `ScreenCapture.CaptureDisplay` → `RealBounds(monitor)` = `min(reported bounds, real framebuffer)`.
- `ScreenCapture.CaptureRegion` also clamps to the live virtual screen (`SM_*VIRTUALSCREEN`) as a backstop.

When reported == real (the normal case) the clamp is a **no-op**, so it can only help, never hurt. Regression test:
`CaptureDisplayIsClampedToRealFramebuffer`.

### Diagnostic scripts (throwaway, in the session scratchpad)

| Script | Purpose | Verdict |
|---|---|---|
| `capdiag.ps1` | PMv2 metrics + primary capture scan | Found the 1500-primary / 1920-secondary dual-mon layout |
| `capdiag2.ps1` | Per-monitor + virtual-desktop black scan | Ambiguous (dark content vs artifact) |
| `capsave.ps1` | Save captures as PNGs to eyeball | Secondary looked black — misleading |
| `capdiff.ps1` | Luma: origin-crop vs offset read | Equal → secondary genuinely dark, scan useless |
| `caplive.ps1` | White window on secondary, offset read | **255.0 → offset reads work; killed the offset hypothesis** |
| `capcaps.ps1` | Per-monitor `CreateDC` + `GetDeviceCaps` | **Confirmed the fix primitive (real framebuffer)** |

---

## Issue 1 — editor "staggering FPS"

**Root cause (from code):** `EditorWindow.OnMove` drew the in-progress shape by re-flattening the *entire document*
to a **full-resolution `RenderTargetBitmap` every mouse-move** (`DocumentRenderer.Render(_document, _baseImage,
preview)`). At 1080p that's an ~8 MB Pbgra32 allocation + full software render per frame → GC thrash → stutter,
scaling with the capture size.

**Fix:** shape tools (arrow / line / rect / filled-rect / ellipse) now draw a **lightweight WPF vector preview**
(`ShowVectorPreview` / `BuildPreviewElements`) on the interaction canvas during the drag — zero per-frame raster.
The shape is flattened into the document only once, on mouse-up, via the **unchanged** `DocumentRenderer`. So the
committed pixels are identical to before; only the live preview mechanism changed. Select-tool **move** was given
the same treatment: render a **one-time pre-flattened background** (base image + all *other* annotations) plus only
the moved annotation, instead of re-flattening the whole document each frame.

---

## Issue 2 — annotations dragged out of the image

**Root cause:** `EditorWindow.Pos` returned the raw pointer; during a drag, `CaptureMouse` keeps delivering points
outside the canvas, so shapes/marquee/counter/text could be placed past the image edge and get clipped/lost on
flatten.

**Fix:** `Pos` clamps to `[0,imgW] × [0,imgH]` (the "wall"), covering draw, marquee, counter, and text placement.
The Select-tool **move** additionally clamps the moved annotation's *bounding box* inside the image
(`MovedWithinBounds`) so an existing annotation can't be shoved off-edge either. The area-selection overlay got the
analogous clamp (`SelectionMath.ClampToBounds`, wired into `SelectionOverlayWindow`) so a drag can't select
off-screen.

---

## Verification

- `dotnet build … -c Release` → **0 warnings / 0 errors**.
- `dotnet test` → **256 passed / 0 failed** (new: `SelectionMath.ClampToBounds` ×3, `Screens.RealFramebufferSize`,
  `ScreenCapture.CaptureDisplayIsClampedToRealFramebuffer`).
- Drove the freshly-built editor via UI Automation: it opens, renders edge-to-edge, and tool-select works. A
  synthetic mouse **drag** can't be injected into WPF in this harness (SendInput moved the cursor correctly and the
  window was foreground, but WPF didn't process the injected button-drag) — however the draw **commit** path is
  byte-for-byte the shipped v1.0 code, so committed drawing is unchanged; only the live preview differs.
- Republished `dist/` and relaunched the tray agent.

## Methodology notes / lessons

- **Read the pixels, not the label.** "Off the screen" vs "black bar" pointed at different subsystems; the taskbar
  cutoff in the screenshot located the bug (capture size > framebuffer) before any code was read.
- **A content-dependent probe is not a proof.** The black-margin scan (Steps 2–3) conflated dark content with a
  black artifact and nearly confirmed a wrong hypothesis. The white-window test removed the content variable and
  gave a clean, unambiguous signal.
- **Reproduce the *runtime*, not just the API.** The diagnostics set PerMonitorV2 first so every measurement matched
  the app's DPI context; a default PowerShell process would have reported virtualized numbers and lied.
- **Prefer a fix that's a no-op in the healthy case.** Clamping to the real framebuffer changes nothing when the
  metrics agree, so it carries no regression risk for the normal single-resolution path.
