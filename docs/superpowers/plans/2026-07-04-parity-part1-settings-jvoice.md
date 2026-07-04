# Parity Part 1 — Settings "JVoice" Monochrome Revamp Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rebuild the macOS Settings window to visually match the Windows port's "JVoice" theme: a pure-black (#000000), 960px-wide, single-scroll, **three-column masonry of titled cards**, using custom monochrome controls — glowing-dot card headers, macOS-style `MonoSwitch` toggles (white track / black knob when on), joined segmented controls, `PillButton`s, per-setting `InfoTip` (ⓘ) tooltips, and a monochrome auto-dismiss slider — replacing today's native SwiftUI 3-tab `TabView`. Behavior stays instant-apply.

**Architecture:** A `SettingsTheme` constants file (all hex/typography/metrics from the spec) + a small set of reusable custom SwiftUI/AppKit components (`DarkSection`, `MonoSwitch` `ToggleStyle`, `SegmentedControl`, `PillButton`, `AccentButton`, `InfoTip`, mono `Slider`, styled combo/field). The view is reassembled as a scrollable three-column card masonry; the window is forced to the dark theme and sized to content. One new persisted setting (`playSound`) is added to `CaptureSettings` with a capture-sound side effect.

**Tech Stack:** Swift 5.9, SwiftUI + AppKit (`NSHostingController`, `NSWindow`, `NSColor`, `NSAppearance`, `NSSound`); TestKit tests for the model change only (UI is verified by build + by-eye against the spec). Build via `scripts/build-app.sh`; tests via `scripts/test.sh`.

**Source spec:** `docs/WINDOWS-TO-MAC-PARITY.md` Part 1 (full palette §1.3, typography §1.4, layout §1.5, components §1.6, exact card contents §1.7). **The exhaustive color/type tables are in that on-branch file — reference them for every hex value; the signature constants are inlined below.**

**Dependency:** Reuses `OverlayDismissScale` from the Part 2 plan (`Packages/CaptureKit/Sources/CaptureKit/OverlayDismissScale.swift`). **Execute the Part 2 plan (at least its Task 1) before Part 1 Task 8**, or add `OverlayDismissScale` first.

**Verified current-state (recon):**
- `App/Settings/SettingsView.swift` — SwiftUI `TabView` with 3 tabs (General/Shortcuts/Recording) at `.frame(width: 480)`; `GeneralTab`/`RecordingTab` use `Form` + stock `Toggle`/`Picker`/`Slider` bound via `bind(_ keyPath:)` helpers that write `store.settings[keyPath:]`/`store.recording[keyPath:]` then `store.persist()` (instant-apply, no `_loading` guard); `ShortcutsTab` is a `VStack` of custom `ShortcutRecorderField` rows using `ShortcutActions` (`update`/`restoreDefaults`/`recordingChanged`); pin-radius is a `Slider(0...20)`; history cap is a pop-up `Picker` 10/50/200; "Clear History…" has a `confirmationDialog`; launch-at-login is a local `@State` backed by `LaunchAtLogin` (not a stored setting).
- `App/Settings/SettingsWindowController.swift` — `NSWindow(contentViewController: NSHostingController(rootView: view))`, style `[.titled, .closable, .miniaturizable]` (NOT resizable), `title = "Settings"`, `w.center()`, `isReleasedWhenClosed = false`; **no explicit size** (derives from the view's `.frame(width: 480)`); default titlebar.
- `App/Settings/SettingsStore.swift` — `@Published settings: CaptureSettings` (key `captureSettings`), `saveDirectory: URL` (key `saveDirectory`), `bindings: HotkeyBindings` (key `hotkeyBindings`), `recording: RecordingConfig` (key `recordingConfig`), `editorStyle: AnnotationStyle` (key `editorDefaultStyle`); `persist()` writes the four dict/URL keys at once; `systemScreenshotLocation()` default save dir. **No sound key.**
- `Packages/CaptureKit/Sources/CaptureKit/CaptureSettings.swift` — struct `CaptureSettings` with `afterCapture`, `format`, `overlayCorner`, `overlayAutoDismissSeconds` (Int, default 6), `pinCornerRadius` (Int, default 8), `pinShadow` (Bool, true), `historyEnabled` (Bool, true), `historyCap` (Int, default 50, **no validation** — 10/50/200 is UI-only); string-dict persistence (`dictionary` / `init(dictionary:)`); `.default`.
- `Packages/RecordingKit/Sources/RecordingKit/RecordingConfig.swift` — `format` (mp4/gif), `fps` (30/60), `systemAudio`, `microphone`, `camera`, `cameraSize` (small/medium), `clickHighlights`, `keystrokeOverlay`, `countdownSeconds` (0/3/5/10).
- `overlayAutoDismissSeconds` is persisted but **unwired** (no consumer, no UI). Part 2 wires the overlay; this plan adds the slider UI.

**TestKit pattern:** `Tests/CaptureKitTests/CaptureSettingsTests.swift` exports `let captureSettingsTests: [TestCase]`, registered in `Tests/CaptureKitTests/main.swift`. Run: `swift run --package-path Packages/CaptureKit CaptureKitTests`.

---

### Task 1: `SettingsTheme` — palette, typography, metrics constants

**Files:**
- Create: `App/Settings/SettingsTheme.swift`

Transcribe the spec's palette (§1.3) and typography (§1.4) into one namespace so every component reads the same values. Include a small `NSColor(hex:)`/`Color(hex:)` helper. (Full table lives in `docs/WINDOWS-TO-MAC-PARITY.md §1.3` — copy all rows; the signature ones are below.)

- [ ] **Step 1: Create the file** with:
  - Colors (SwiftUI `Color` from hex): `windowBG #000000`, `chrome #0A0A0A`, `card #0E0E0E`, `controlRest #1A1A1A`, `controlHover #242424`, `controlPressed #2E2E2E`, `border #2A2A2A`, `textPrimary #F5F5F7`, `label #D9D9D9`, `headerLabel #8E8E93`, `subLabel #6E6E73`, `faint #595959`, `accent #FFFFFF`, `accentHover #E6E6E6`, `accentPressed #CFCFCF`. Alpha-literals: `segmentHover #12FFFFFF`, `segmentChecked #29FFFFFF`, `pillFill #1FFFFFFF`, `pillHover #2BFFFFFF`, `pillPressed #3AFFFFFF`, `pillBorder #3DFFFFFF`, `switchOffKnob #CFCFCF`, `infoIdle #1FFFFFFF`, `infoHover #40FFFFFF`, `infoRing #40FFFFFF`, `infoGlyph #E6FFFFFF`.
  - Typography sizes/weights per §1.4 (header 18 bold, card header 10 bold uppercased, field label 11.5 semibold, row title 12.5 medium, sub-label 10.5, segment 12, slider value 12 semibold, pill 12 semibold, tooltip title 12.5 semibold / body 11.5 / example 11 italic).
  - Metrics: card radius 10, card border 1, window width 960, outer margin 18, column width ≈297, gutter 16, vertical gap 12, MonoSwitch 38×22 r11 knob 18×18, segment radius 6, pill radius 7, InfoTip 16 r8, slider track 4 r2 thumb 16.
  - A `Color(hex: UInt32, alpha:)` helper (ARGB or RGB+alpha).

- [ ] **Step 2: Build.** `scripts/build-app.sh` clean (file compiles even if unused yet).
- [ ] **Step 3: Commit**

```bash
git add App/Settings/SettingsTheme.swift
git commit -m "feat(settings): JVoice theme constants (palette/type/metrics) (parity P1)"
```

---

### Task 2: Add `playSound` capture setting + play a sound on capture

**Files:**
- Modify: `Packages/CaptureKit/Sources/CaptureKit/CaptureSettings.swift`
- Test: `Packages/CaptureKit/Tests/CaptureKitTests/CaptureSettingsTests.swift`
- Modify: `App/Capture/CaptureCoordinator.swift` (play the sound after a screenshot)

Spec §1.9 (adopted decision: add the setting + sound, default **on**, matching Windows).

- [ ] **Step 1: Add failing test** (append to `captureSettingsTests`):

```swift
    TestCase("playSoundDefaultsOnAndRoundTrips") { t in
        t.isTrue(CaptureSettings.default.playSound)
        var s = CaptureSettings.default
        s.playSound = false
        let back = CaptureSettings(dictionary: s.dictionary)
        t.isFalse(back.playSound)
    },
```

- [ ] **Step 2: Run → FAIL** (`playSound` undefined). `swift run --package-path Packages/CaptureKit CaptureKitTests`.

- [ ] **Step 3: Implement** — add `public var playSound: Bool` to the struct; default `true` in `.default` and the memberwise init; persist in `dictionary` (`"playSound": playSound ? "1" : "0"`) and parse in `init(dictionary:)` (`(dictionary["playSound"] ?? "1") != "0"`, so missing key = on). Keep all other fields untouched.

- [ ] **Step 4: Run → PASS.**

- [ ] **Step 5: Play the sound** — in `App/Capture/CaptureCoordinator.swift`, on the successful screenshot path (where the image is produced, before/around `presentOverlay`), add: `if settings.settings.playSound { NSSound(named: "Grab")?.play() ?? NSSound(named: "Tink")?.play() }`. (Use a real system sound name available on macOS 14; `Tink` is a safe fallback. Do NOT play for the OCR/Capture-Text path.)

- [ ] **Step 6: Build + verify.** `scripts/build-app.sh`; take a screenshot → a sound plays; toggle off later → silent.

- [ ] **Step 7: Commit**

```bash
git add Packages/CaptureKit/Sources/CaptureKit/CaptureSettings.swift \
        Packages/CaptureKit/Tests/CaptureKitTests/CaptureSettingsTests.swift \
        App/Capture/CaptureCoordinator.swift
git commit -m "feat(capture): add play-sound-on-capture setting, default on (parity P1)"
```

---

### Task 3: `MonoSwitch` — custom `ToggleStyle` (signature element)

**Files:**
- Create: `App/Settings/Components/MonoSwitch.swift`

Spec §1.6. Track 38×22 r11. OFF: track `#2A2A2A`, knob 18×18 `#CFCFCF`, left (2px inset). ON: track `#FFFFFF`, knob 18×18 `#000000`, right (2px inset). Disabled → 40% opacity; pointing-hand cursor. A native SwiftUI `Toggle` can't invert track+knob, so build a `ToggleStyle`.

- [ ] **Step 1: Implement** a `struct MonoSwitchStyle: ToggleStyle` drawing the track `RoundedRectangle(cornerRadius: 11)` filled `configuration.isOn ? SettingsTheme.accent : SettingsTheme.border`, and a `Circle()` knob (18) filled `configuration.isOn ? .black : SettingsTheme.switchOffKnob`, offset left/right by 2px, with `.animation` on `isOn`, `.onTapGesture { configuration.isOn.toggle() }`, `.opacity(isEnabled ? 1 : 0.4)`, `.pointerStyle`/tracking cursor.
- [ ] **Step 2: Build.** `scripts/build-app.sh` clean.
- [ ] **Step 3: Commit**

```bash
git add App/Settings/Components/MonoSwitch.swift
git commit -m "feat(settings): MonoSwitch toggle style (parity P1)"
```

---

### Task 4: `SegmentedControl` — joined monochrome segments

**Files:**
- Create: `App/Settings/Components/SegmentedControl.swift`

Spec §1.6. A generic `SegmentedControl<T: Hashable>` binding a selection over `[(value: T, label: String or glyph)]`. Each segment: 1px `#2A2A2A` border, inset ~8,5, text `12 #D9D9D9`; resting fill `#0A0A0A`, hover `#12FFFFFF`; **selected fill `#29FFFFFF`, text `#FFFFFF`**. Corners rounded only on the ends (left seg rounds left r6, right seg rounds right, middles square; solo rounds all four). Support glyph segments (the corner arrows ↖↗↙↘ 15pt).

- [ ] **Step 1: Implement** the view (an `HStack(spacing: 0)` of segment buttons with per-position corner masking via a custom `RoundedCorners` shape or `clipShape` with `UnevenRoundedRectangle`). Selecting a segment sets the binding.
- [ ] **Step 2: Build.** clean.
- [ ] **Step 3: Commit**

```bash
git add App/Settings/Components/SegmentedControl.swift
git commit -m "feat(settings): joined monochrome SegmentedControl (parity P1)"
```

---

### Task 5: `PillButton` + `AccentButton`

**Files:**
- Create: `App/Settings/Components/PillButtons.swift`

Spec §1.6. `PillButton`: text `12 SemiBold #F5F5F7`, inset ~12,6, radius 7, 1px border; fill `#1FFFFFFF`, border `#3DFFFFFF`, hover `#2BFFFFFF`, pressed `#3AFFFFFF`, disabled 40%. `AccentButton`: white fill `#FFFFFF`, black text `#0A0A0A`, no border, radius 6, inset ~12,5, size 13; hover `#E6E6E6`, pressed `#CFCFCF`.

- [ ] **Step 1: Implement** both as `ButtonStyle`s (or small views) reading `SettingsTheme`.
- [ ] **Step 2: Build.** clean.
- [ ] **Step 3: Commit**

```bash
git add App/Settings/Components/PillButtons.swift
git commit -m "feat(settings): PillButton + AccentButton (parity P1)"
```

---

### Task 6: `InfoTip` (ⓘ) + hover tooltip + help copy

**Files:**
- Create: `App/Settings/Components/InfoTip.swift`
- Create: `App/Settings/SettingsHelp.swift` (the per-setting + per-shortcut copy)

Spec §1.6/§1.7. A 16px circle (r8), idle `#1FFFFFFF`, hover `#40FFFFFF`, 1px `#40FFFFFF` ring, **normal arrow cursor**; glyph a small serif "i" (`#E6FFFFFF`) — on macOS render an SF Symbol `info` or an attributed serif "i". Tooltip on hover (~120ms): `#0E0E0E` card (1px `#2A2A2A`, r6, inset 8,5), max width ~300, with Title (12.5 SemiBold `#F5F5F7`), Explanation (11.5 `#D9D9D9`), optional "e.g. …" Example (11 Italic `#6E6E73`).

- [ ] **Step 1: Implement `InfoTip`** taking `title/explanation/example` and showing the tooltip via a hover `.popover`/overlay with the ~120ms delay.
- [ ] **Step 2: Write `SettingsHelp`** — a struct/dictionary mapping each setting + each shortcut action to `{title, explanation, example}`. Port concise copy for: After a capture, Image format, Play sound, Screen corner, Auto-dismiss, Pin corner radius, Drop shadow, Remember history, Keep at most, Launch at login, Save location, Recording format/frame rate/system audio/microphone/camera bubble/camera size/highlight clicks/show keystrokes/countdown, and each shortcut action. One sentence + one concrete "e.g." each. (Windows source `windows/src/BetterScreenshot.App/Settings/SettingsWindow.xaml`/`.xaml.cs` `ShortcutHelp` has verbatim copy if that tree is available; otherwise write equivalents.)
- [ ] **Step 3: Build.** clean.
- [ ] **Step 4: Commit**

```bash
git add App/Settings/Components/InfoTip.swift App/Settings/SettingsHelp.swift
git commit -m "feat(settings): InfoTip tooltip + per-setting help copy (parity P1)"
```

---

### Task 7: `DarkSection` card (glowing-dot header)

**Files:**
- Create: `App/Settings/Components/DarkSection.swift`

Spec §1.6. Rounded rect r10, fill `#0E0E0E`, 1px `#2A2A2A` border. Header row (inset ~14,10): a 5×5 white dot with a soft glow (white circle + blur/shadow radius ~7, white @60%) + 8px gap + UPPERCASED title (10 Bold `#8E8E93`). 1px `#2A2A2A` hairline under the header, full width. Content inset 14,12,14,14.

- [ ] **Step 1: Implement** `DarkSection<Content: View>(_ title: String, @ViewBuilder content:)` with the glow via `.shadow`/blur on a small `Circle`.
- [ ] **Step 2: Build.** clean.
- [ ] **Step 3: Commit**

```bash
git add App/Settings/Components/DarkSection.swift
git commit -m "feat(settings): DarkSection card with glowing-dot header (parity P1)"
```

---

### Task 8: Monochrome slider + styled combo/text field

**Files:**
- Create: `App/Settings/Components/MonoSlider.swift`
- Create: `App/Settings/Components/MonoField.swift` (styled ComboBox + TextField)

Spec §1.6. Slider: base track 4px r2 `#1AFFFFFF`, filled portion 4px white `#FFFFFF`, thumb 16 white (hover `#E6E6E6`, drag `#CFCFCF`). The auto-dismiss slider maps via `OverlayDismissScale` (positions 2…31; `label(seconds)` → "Never"/"{n}s"). Combo: h~30, fill `#1A1A1A`, 1px `#2A2A2A`, r6, chevron `#8E8E93`; popup `#0E0E0E`, highlight `#29FFFFFF`. Text field: fill `#0A0A0A`, 1px `#2A2A2A`, r6, inset 8,4, focus border → white.

- [ ] **Step 1: Implement `MonoSlider`** (a `Slider`-style control over an `Int` position range with a value-label closure) — for auto-dismiss, drive positions `2...31` and display `OverlayDismissScale.label(OverlayDismissScale.positionToSeconds(position))`, persisting `overlayAutoDismissSeconds = OverlayDismissScale.positionToSeconds(position)`.
- [ ] **Step 2: Implement `MonoField`** — a styled `Menu`/`Picker`-backed combo (for Pin corner radius 0/4/8/12/16/20) and a styled read-only text field (for the Save path).
- [ ] **Step 3: Build.** clean.
- [ ] **Step 4: Commit**

```bash
git add App/Settings/Components/MonoSlider.swift App/Settings/Components/MonoField.swift
git commit -m "feat(settings): mono slider (OverlayDismissScale) + styled combo/field (parity P1)"
```

---

### Task 9: `SettingsWindowController` — 960 width, size-to-content, dark, non-resizable

**Files:**
- Modify: `App/Settings/SettingsWindowController.swift`

Spec §1.5. Force the dark theme (adopted decision: ignore system light/dark). Keep style `[.titled, .closable, .miniaturizable]` (no `.resizable`). Width 960; height sizes to content, clamped to ~98% of the screen work-area height (then the inner `ScrollView` engages). Dark titlebar.

- [ ] **Step 1: Force dark appearance** — set `hostingController.view.appearance = NSAppearance(named: .darkAqua)` and `window.appearance = NSAppearance(named: .darkAqua)`.
- [ ] **Step 2: Dark titlebar** — `window.titlebarAppearsTransparent = true` + a dark background, or set `window.backgroundColor = .black`; keep `title = "Settings"`.
- [ ] **Step 3: Size** — set content width 960; let the SwiftUI root drive height (it uses a `ScrollView`), and clamp the window height to `screen.visibleFrame.height * 0.98` via `setContentSize`/`setFrame` after first layout. Re-`center()`.
- [ ] **Step 4: Build + verify.** `scripts/build-app.sh`; open Settings → 960-wide, pure-black, dark titlebar, not width-resizable, close button reachable on a small screen.
- [ ] **Step 5: Commit**

```bash
git add App/Settings/SettingsWindowController.swift
git commit -m "feat(settings): 960 dark size-to-content settings window (parity P1)"
```

---

### Task 10: Reassemble the view — three-column card masonry (replaces the TabView)

**Files:**
- Modify: `App/Settings/SettingsView.swift` (replace the whole `TabView`; keep the `bind(...)` instant-apply helpers and the `store`/`actions` inputs)

Spec §1.5/§1.7. Inside an 18px outer margin, in a `ScrollView`: a header block (title "BetterScreenshot" 18 Bold white + subtitle 11.5 `#6E6E73`), then a three-column layout (≈297px columns, 16px gutters, 12px vertical gaps) of `DarkSection` cards, then a full-width Keyboard Shortcuts card, then the footer "Changes apply immediately." (11 `#6E6E73`). Wire every control to the existing store keypaths via the existing `bind(...)` helpers (instant-apply preserved). Each label gets an `InfoTip` using `SettingsHelp`.

- [ ] **Step 1: Header + scroll shell + column layout** (Column A: Capture · Quick Access Overlay · Pin to Screen; Column B: History · Startup · Save Location; Column C: Recording).
- [ ] **Step 2: Card 1 CAPTURE** — field "After a capture" → 4-segment Overlay|Copy|Save|Both (`afterCapture`); "Image format" → 2-segment PNG|JPG (`format`); "Play a sound on capture" → `MonoSwitch` (`playSound`, Task 2).
- [ ] **Step 3: Card 2 QUICK ACCESS OVERLAY** — "Screen corner" → 4-segment ↖↗↙↘ (`overlayCorner`); "Auto-dismiss after" → `MonoSlider` + value label via `OverlayDismissScale`, persisting `overlayAutoDismissSeconds`.
- [ ] **Step 4: Card 3 PIN TO SCREEN** — "Corner radius" → `MonoField` combo 0/4/8/12/16/20 (`pinCornerRadius`) [adopted decision: combo, not slider]; "Drop shadow" → `MonoSwitch` (`pinShadow`).
- [ ] **Step 5: Card 4 HISTORY** — "Remember capture history" (+ sub-label) → `MonoSwitch` (`historyEnabled`); "Keep at most" → 3-segment **10 | 50 | 100** (`historyCap`) [200→100 adopted; satisfies Part 3 Task 5].
- [ ] **Step 6: Card 5 STARTUP** — "Launch at login" (+ sub-label) → `MonoSwitch` bound to `LaunchAtLogin.isEnabled`/`setEnabled` (keep the existing equality guard).
- [ ] **Step 7: Card 6 SAVE LOCATION** — sub-label + current path in a `MonoField` text field + `PillButton "Browse…"` (opens `NSOpenPanel`, folders only → `store.saveDirectory`).
- [ ] **Step 8: Card 7 RECORDING** — Format 2-seg MP4|GIF; Frame rate 2-seg 30|60; hairline; MonoSwitches system audio / microphone / camera bubble; Camera size 2-seg Small|Medium (disabled when camera off); MonoSwitches highlight clicks / show keystrokes (**keep the macOS Accessibility-permission gate + caption** — the existing special binding); Countdown 4-seg Off|3s|5s|10s. All bound to `store.recording` keypaths.
- [ ] **Step 9: Card 8 KEYBOARD SHORTCUTS (full-width)** — sub-label; rows two-per-row: action title (12.5) + `InfoTip`, a mono chip (`#0A0A0A` pill, 1px `#2A2A2A`, r6, min-width ~118, mono 12) showing the combo or "(unbound)", a "Change" `PillButton`, a "Clear" button. **Reuse the existing `ShortcutRecorderField` live-rebind logic** (`ShortcutActions.update`/`recordingChanged`/conflict alert/suspend-resume) — just restyle the row (chip + Change/Clear) instead of the plain field. Actions: Capture Area, Capture Window, Capture Fullscreen, Capture Text, Pin from Clipboard, Record, Open History, Restore Recently Closed, Pause/Resume Recording.
- [ ] **Step 10: Keep "Clear History…"** guarded by its existing `confirmationDialog` (no red button — monochrome + guarded).
- [ ] **Step 11: Build + verify.** `scripts/build-app.sh`; open Settings — see the verification checklist below. Change several values, reopen → they stuck. Rebind a hotkey → still works. Clear History → still confirms.
- [ ] **Step 12: Commit**

```bash
git add App/Settings/SettingsView.swift
git commit -m "feat(settings): three-column JVoice card masonry replaces tabbed settings (parity P1)"
```

---

## Verification checklist (Part 1) — spec §1 "by eye"
- [ ] `scripts/test.sh` green (incl. the `playSound` round-trip test).
- [ ] `scripts/build-app.sh` clean.
- [ ] Pure-black 960 window; three-column card masonry; glowing-dot card headers; white/black `MonoSwitch`es (no native green toggles); segmented controls (selected = white-16% fill + white text); ⓘ tooltips on hover; auto-dismiss slider reading "Never"/"{n}s"; Pin radius combo; History cap 10/50/100.
- [ ] Instant-apply (change a value, reopen — it stuck); live hotkey rebind still works; "Clear History…" still confirms.
- [ ] No white-on-white, no native green toggles, no system-blue accents; window ignores system light/dark (always black).

## Assumptions logged (adopted from spec §1.9 / "Assumptions & open questions")
- **Forced dark theme** on the Settings window (ignores system appearance) to match Windows.
- **`playSound` added** (default on) with a system capture sound.
- **Pin corner radius → combo** (0/4/8/12/16/20), matching Windows.
- **History cap third option 200 → 100** (also satisfies Part 3 Task 5).
- Custom components live under `App/Settings/Components/`; theme + help copy under `App/Settings/`.
