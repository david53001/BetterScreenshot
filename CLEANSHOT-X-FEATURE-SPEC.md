# CleanShot X — Feature Inventory & Replication Spec

> Purpose: a replication-ready spec of CleanShot X's (macOS, by MakeWeb.eu) **non-cloud** features, for building a free clone ("BetterScreenshot").
> Cloud features (CleanShot Cloud upload, share links, account sync) are **out of scope** and only flagged where they intersect a kept feature.
>
> Sourcing: built primarily from CleanShot's own materials — the [features page](https://cleanshot.com/features), [changelog](https://cleanshot.com/changelog), and the [URL-scheme API docs](https://cleanshot.com/docs-api) — cross-checked against independent reviews (daveswift.com, Setapp, Macworld, The Sweet Setup, podfeet.com, 9to5Mac). Each feature below was adversarially verified; items that failed verification are listed under **Unverified / Refuted** and should NOT be treated as fact. Feature set tracked to ~v4.8 (mid-2025).

---

## 1. Screenshot Capture Modes

| Mode | What it does | Notes for implementation |
|---|---|---|
| **Capture Area** (region) | User drags a rectangle to select a region. Core capture mode. | Resizable/movable selection before commit. URL: `capture-area` with optional `x,y,width,height,display` for instant capture, and `action=copy\|save\|annotate\|pin` (`upload` is cloud — skip). |
| **Capture Fullscreen** | Captures the entire display. | Multi-display aware (`display` param). URL: `capture-fullscreen`. |
| **Capture Window** | Captures a single window; hover to highlight the target window, click to capture. | URL: `capture-window`. (Default transparent-background/auto-shadow behavior is **unverified** — see §13.) |
| **Repeat Previous Area** | Re-captures the exact last-used region without re-selecting. | URL: `capture-previous-area`. Store last region rect. |
| **Self-Timer** | Capture-Area mode with a delayed trigger, for capturing menus/hover/transient states. | URL: `self-timer`. Whether the delay value is user-configurable is **unverified** (public docs say only "a specified delay"). |
| **Scrolling Capture** | Captures content taller (or wider) than the viewport by auto-scrolling and stitching frames into one long image. | URL: `scrolling-capture` with `x,y,width,height,display`, plus `start` and `autoscroll` (v4.7+). The hard part is frame stitching/overlap detection. |

### Capture aids (toggleable on the capture overlay)
- **Crosshair** — precision cursor for selecting region edges.
- **Magnifier / loupe** — zoomed pixel view "for pixel-perfect capture."
- **Freeze Screen** — pauses/snapshots the screen so moving content (video, animations, hover menus) can be captured precisely while selecting.

---

## 2. Screen Recording

| Capability | Details |
|---|---|
| **Output formats** | MP4 (H.264) video **or** optimized GIF. |
| **Capture targets** | Window, fullscreen, or custom-area dimensions. |
| **Quality controls** | Adjustable quality, FPS, and resolution. |
| **Audio** | Microphone **and** macOS system/computer audio. (macOS may restrict simultaneous mic + system audio depending on OS version — design around this.) |
| **Built-in video editor** | Trim; change quality; change resolution; mute audio; convert stereo→mono. |
| **Bindable recording commands** | Record Screen / Stop, Select Window, Start Video Recording, Start GIF Recording, Pause/Resume, Restart, Toggle Camera Fullscreen. |
| **Countdown** | Optional countdown before recording starts (v4.6). |
| **Menu-bar timer** | Shows elapsed recording time in the menu bar. |
| **Auto Do-Not-Disturb** | Automatically suppresses notifications while recording. |
| **Hide desktop clutter** | Optionally hides desktop icons during recording (see §8). |

### Recording overlays
- **Webcam / camera overlay** — adjustable position, size, shape (circular / square / vertical), plus a fullscreen camera mode.
- **Mouse-click visualization** — customizable color, size, style (outline/filled), and an enable/disable animation toggle.
- **Keystroke display** — shows pressed keys on screen; configurable position, size, style (dark/light), and "all keys" vs "only command keys."

---

## 3. Annotate Editor

A full editor that opens on a fresh capture, an existing file, or a clipboard image.

**Tools:**
- **Crop** — with aspect-ratio option and snapping to edges.
- **Arrow** — 4 styles including curved; thickness & curvature controls.
- **Rectangle**, **Filled Rectangle**, **Ellipse**, **Line**.
- **Pencil** — freehand with auto-smoothing.
- **Highlighter** — adjustable opacity.
- **Pixelate** — applied with randomization (anti-reconstruction); also a **Gaussian blur** option.
- **Blur** — "secure" and "smooth" options for redaction.
- **Spotlight** — dims everything except a highlighted region.
- **Counter** — numbered step markers for tutorials; configurable style and starting number.
- **Text** — 7 predefined styles; font size & color.
- **Emoji** insertion.
- **Color picker** — select and save custom colors.

**Transforms & canvas:**
- Image **resize**, **rotate / flip** (v4.8).
- Object-level and selection-level editing (move, duplicate, restyle individual objects).
- **Combine multiple screenshots** into one by drag-and-dropping another screenshot into the Annotate window.
- Save as **editable CleanShot project files** (re-openable for further editing) in addition to flat image export.

**Editor file/object shortcuts (fixed, standard macOS conventions):**
`Cmd+C` copy object · `Cmd+D` duplicate object · `Cmd+S` save · `Cmd+Shift+S` save as · `Cmd+Shift+C` copy screenshot to clipboard · `Cmd+P` print · `Shift+Cmd+I` add new screenshot · `Cmd+I` add screenshot from file.
> Note: per-tool **single-letter** shortcuts (B/V/K/D/M/L/T/A/C/E/P/H/R/F) were **refuted** — do not assume those specific bindings exist.

---

## 4. Background / Wallpaper Styling

Turns a raw screenshot into a polished, shareable image (the "social-media post" look).
- **Background tool** (v4.5): preset **gradient** and **solid-color** backgrounds (10+ presets added over versions).
- Adjustable **padding** around the screenshot.
- **Rounded corners** with configurable corner radius.
- Toggleable **drop shadow**.
- **Editable window screenshots** (v4.8): change or remove a window's background after capture.

---

## 5. OCR / Capture Text

- Extracts non-selectable text from on-screen content (images, scanned docs, video frames, protected areas), **entirely on-device** (v3.8).
- User drags to select a region; recognized text is copied **directly to the clipboard**.
- **Automatic language detection** (v4.8).
- **QR-code reader** (v4.6).
- URL: `capture-text` — opens the OCR tool interactively, or extracts from a file (`filepath, x, y, width, height, display, linebreaks=keep|remove`). Requires macOS 10.15+.
> Implementation: macOS Vision framework (`VNRecognizeTextRequest`) covers this natively.

---

## 6. Quick Access Overlay (post-capture)

- After every capture, a floating **thumbnail appears in a screen corner** before saving/annotating.
- From the overlay, instantly: **save**, **copy to clipboard**, **annotate**, or **drag-and-drop** the file directly into other apps. All local — no cloud required.
- **Capture History** stores recent captures (up to ~1 month).
- **Restore Recently Closed File** — brings back an overlay you accidentally dismissed.
- Can be populated programmatically via `add-quick-access-overlay` (`filepath` to a PNG/JPEG/MP4).

---

## 7. Pin to Screen

- Pin a capture as a floating, **always-on-top** overlay on the desktop.
- Pinned items support adjustable corner radius and a toggleable shadow.
- URL: `pin` (optional `filepath`).

---

## 8. Desktop Cleanup

- **Hide desktop icons** before capturing/recording for a clean background.
- URLs: `toggle-desktop-icons`, `hide-desktop-icons`, `show-desktop-icons`.

---

## 9. All-In-One Capture Mode

- A unified capture overlay for choosing screenshot vs. recording vs. other actions from one entry point.
- URL: `all-in-one` (confirmed). 
> Note: the specific claim that it shipped in v4.2 with a "hold Command for crosshair" mode was **refuted** — the mode exists, but treat those specifics as unverified.

---

## 10. App Shell & Automation

- **Menu-bar app** exposing all capture/recording/OCR/pin/desktop-icon actions; shows the recording timer in the menu bar.
- **`cleanshot://` URL scheme** — a documented API of distinct commands with optional parameters, enabling integration with launchers (Alfred, Raycast, LeaderKey) and scripting, with **no cloud dependency**.
- **Customizable hotkeys** — capture and recording commands are user-bindable in a Shortcuts preferences pane (each command has a default binding).

### `cleanshot://` command surface (replication checklist)
`capture-area` · `capture-previous-area` · `capture-fullscreen` · `capture-window` · `self-timer` · `scrolling-capture` · `all-in-one` · `capture-text` · `pin` · `open-annotate` (open a file in editor) · `open-from-clipboard` (v3.5.1+) · `add-quick-access-overlay` · `toggle-desktop-icons` · `hide-desktop-icons` · `show-desktop-icons`
> Cloud-only commands/values to **skip**: the `action=upload` value on `capture-area`, and any "Upload to Cloud" shortcut.

---

## 11. Export, Save & After-Capture (partially verified)

Confirmed: still images export to **PNG/JPG**; "after capture" actions include **copy to clipboard**, **save**, **annotate**, **pin**, and **drag-and-drop** from the overlay. Recordings export to **MP4/GIF**.

> **Not independently verified** (open questions — see §13): WebP support, exact image quality/compression options, file-naming template tokens, and custom save-destination configuration. These are standard expectations but weren't confirmed in the surviving evidence, so verify before treating as spec.

---

## 12. Core vs. Nice-to-Have (suggested build order)

**Core (defines the CleanShot identity — build first):**
- Area / window / fullscreen capture with crosshair + magnifier
- Scrolling capture
- Self-timer, freeze-screen
- Quick Access Overlay (save / copy / drag-and-drop)
- Annotate editor (arrows incl. curved, shapes, line, pencil, highlighter, pixelate/blur, spotlight, counter, text, crop, color picker)
- Screen recording → MP4 + GIF (window/fullscreen/area), mic + system audio, trim editor
- OCR Capture Text → clipboard
- Configurable hotkeys + menu-bar app
- Local save destinations & after-capture actions
- Pin-to-screen, hide-desktop-icons

**Nice-to-have (polish / differentiators):**
- Webcam overlay
- Mouse-click & keystroke visualization
- Countdown + pause/resume/restart recording controls
- Auto Do-Not-Disturb
- Background/wallpaper styling (padding, rounded corners, shadows)
- Editable window backgrounds
- Combine-multiple-screenshots + editable project files
- Rotate/flip, emoji
- QR-code reading, auto OCR language detection
- Capture history + restore-recently-closed
- Full `cleanshot://` URL-scheme automation API

---

## 13. Unverified / Refuted (do NOT treat as fact)

**Refuted (3-vote verification rejected these):**
1. All-In-One arrived in **v4.2** with a **hold-Command crosshair** mode. (The mode exists; these specifics do not check out.)
2. The editor assigns specific **single-letter tool shortcuts** (B/V/K/D/M/L/T/A/C/E/P/H/R/F).
3. **Window capture** auto-produces a **transparent background + automatic drop shadow**.

**Open questions to resolve before building those areas:**
- Exact default export formats (WebP?) and image quality/compression options.
- File-naming template tokens and custom save-destination settings.
- Whether the self-timer delay is user-configurable or a fixed preset.
- The precise transparent-background/shadow behavior of window capture.
- The full **default** hotkey map for capture/recording commands (only the editor file/object shortcuts are documented).

---

## 14. Excluded (Cloud — intentionally out of scope)
CleanShot Cloud uploads, shareable links, annotation comments on cloud links, account/subscription sync. The app itself notes "Using Cloud isn't required to use the app," so the entire local feature set above stands alone.
