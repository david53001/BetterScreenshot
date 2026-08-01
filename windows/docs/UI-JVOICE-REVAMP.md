# Windows UI — JVoice Monochrome Revamp (2026-07-03)

> **Goal.** Re-skin the BetterScreenshot **Windows** app (`windows/`, .NET 9 + WPF, branch
> `windows-port`) to adopt the visual language of the sibling app **JVoice-Windows**
> (`C:\Users\david_v0a3rlc\Sorted\Coding\Apps\JVoice-Windows`), which the owner likes — a
> **pure black-and-white monochrome** system. The previous revamp (see `UI-REVAMP-SPEC.md`) gave
> the app a dark macOS-HIG theme with a **blue** (`#0A84FF`) accent; this revamp replaces that with
> JVoice's monochrome identity, **especially in Settings**, which becomes a card-based layout.
>
> **Scope decision (logged, owner away):** this touches **only the Windows port**. JVoice's reference
> that I can see and verify is its *Windows* WPF app; I'm on a Windows machine and can build/run/screenshot
> WPF but not the macOS Swift app. The macOS app (behavioral source of truth) is intentionally left
> untouched. If the owner wants the macOS SwiftUI app re-skinned too, that's a separate pass.

## JVoice's design language (studied from its source)

Files studied: `JVoice.App/UI/Styles/JVoicePalette.xaml`, `JVoice.App/UI/SettingsView.xaml`,
`JVoice.App/UI/DarkSection.cs`, `Converters.cs`.

1. **Pure monochrome.** Every former per-section accent (blue/green/purple/…) collapses to **white**.
   The palette is black → near-black → grayscale text, with white as the single "accent."
   - Panel background `#000000`, section/card `#0E0E0E`, input recess `#080808`, border `#262626`,
     header text `#9A9A9A`, grayscale text ladder `W85 #D9D9D9 · W75 #BFBFBF · W45 #737373 · W40 #666
     · W38 #616161 · W35 #595959`.
2. **DarkSection** — a titled dark **card**: rounded 10, header row = a **small (5px) glowing white
   dot** + a tiny (9.5px) **bold UPPERCASED** gray label, a 0.5px hairline divider, then padded content.
   It's a templated `ContentControl` (keeps the declaring file's namescope so named children work).
3. **MonoSwitch** — a `CheckBox` rendered as a macOS toggle: OFF = dark track + light-gray knob,
   ON = **white track + black knob** (the signature inversion). 38×22, r11.
4. **Segmented control** — joined `RadioButton` row (`SegmentLeft/Mid/Right`, rounded only on the ends);
   resting = input recess, **checked = white@16% fill + white text**.
5. **Buttons** — `PressableButton` (chromeless, scales to 0.97 + 0.85 opacity on press);
   `DarkPrimaryButton` (white text, white@12% fill, white@28% border, r7, font 11 semibold);
   `DarkDestructiveButton` (monochrome — white text, white@10% fill, white@24% border; guarded by an
   OK/Cancel dialog rather than color).
6. **Mono scrollbar** — transparent track, thin rounded white-at-low-opacity thumb, no arrows.
7. **Layout** — Settings is a single scroll: full-width header, a multi-column **masonry** of cards,
   full-width footer. Sizes to content; window clamps `MaxHeight` to the work area so the ✕ is reachable.

## Mapping onto BetterScreenshot

BetterScreenshot centralizes everything in `Resources/Theme.xaml` with **implicit styles** (full
ControlTemplates) so every window restyles by changing tokens — no per-call-site edits. Strategy:
**keep the token keys, change their values to monochrome, and fix the few styles that would produce
white-on-white now that the accent is white.**

### Palette remap (`Resources/Theme.xaml`) — keys unchanged

| Key | Old (blue theme) | New (monochrome) | Note |
|-----|------------------|------------------|------|
| `Theme.WindowBrush` | `#232326` | `#000000` | pure black window |
| `Theme.ChromeBrush` | `#1C1C1F` | `#0A0A0A` | bars/footers; also the recessed input fill |
| `Theme.CardBrush` | `#2C2C30` | `#0E0E0E` | floating cards, popups, sections |
| `Theme.ControlBrush` | `#3A3A3F` | `#1A1A1A` | resting button/combo fill |
| `Theme.ControlHoverBrush` | `#47474D` | `#242424` | hover |
| `Theme.ControlPressedBrush` | `#525259` | `#2E2E2E` | pressed |
| `Theme.SubtleHoverBrush` | `#1AFFFFFF` | `#1AFFFFFF` | unchanged |
| `Theme.SubtlePressedBrush` | `#2BFFFFFF` | `#2BFFFFFF` | unchanged |
| `Theme.BorderBrush` | `#26FFFFFF` | `#2A2A2A` | opaque hairline (JVoice-like) |
| `Theme.TextBrush` | `#F2F2F5` | `#F5F5F7` | primary text |
| `Theme.SecondaryTextBrush` | `#9A9AA2` | `#8E8E93` | labels |
| `Theme.AccentBrush` | `#0A84FF` | `#FFFFFF` | **white is the accent** |
| `Theme.AccentHoverBrush` | `#2B94FF` | `#E6E6E6` | dim-white hover |
| `Theme.AccentPressedBrush` | `#0870DB` | `#CFCFCF` | dim-white pressed |
| `Theme.DangerBrush` | `#FF453A` | `#FF453A` | kept (History warn badge); DangerButton goes mono |
| `Theme.ScrollThumbBrush` | `#33FFFFFF` | `#33FFFFFF` | unchanged |
| `Theme.SegmentTrackBrush` | `#1AFFFFFF` | `#1AFFFFFF` | unchanged |

New grayscale text tokens (JVoice ladder, for the Settings hierarchy):
`Theme.TextStrongBrush #FFFFFF · Theme.TextW85 #D9D9D9 · Theme.SubtleTextBrush #6E6E73 · Theme.FaintTextBrush #595959`.

### White-on-white fixes (implicit styles)

Because the accent is now white, any style that put **white content on an accent fill** must change:

- `Theme.AccentButton` → **white fill + black text** (`#0A0A0A`), hover `#E6E6E6`, pressed `#CFCFCF`.
  A crisp monochrome primary (Copy in editor, Start in Welcome).
- `ToggleButton` (implicit) & `Theme.ToolButton` **checked** → **white@20% fill (`#33FFFFFF`)** + a
  1px white@24% border, content stays light (not a full white fill). The editor already brightens the
  active tool's glyph to pure white (`EditorWindow.xaml.cs:168`), which reads well on the translucent fill.
- `ComboBoxItem` **highlighted** → white@16% (`#29FFFFFF`) instead of accent fill; text stays light.
- `CheckBox` (implicit, raw) **checked** → white fill + **black** check `Path`.
- `TextBox` focus border → white (visible, kept).
- `Theme.DangerButton` → monochrome (white text, `#14FFFFFF` fill, `#3DFFFFFF` border, r6). Destructive
  actions stay guarded by their existing confirm dialogs (History "Clear All…", etc.).

### New components (added to `Resources/Theme.xaml`)

- **`DarkSection`** control ported to `Controls/DarkSection.cs` (namespace `BetterScreenshot.App.Controls`)
  + implicit style using theme tokens (card `CardBrush`, border `BorderBrush`, header `SecondaryTextBrush`,
  white glowing dot). Uppercases its `HeaderText`. All dots are white (uniform, per JVoice).
- **`Theme.MonoSwitch`** — CheckBox → macOS toggle (OFF `#2A2A2A` track + `#CFCFCF` knob; ON white track
  + black knob).
- **`Theme.SegmentLeft/Mid/Right`** — joined RadioButton segments (recess `#0A0A0A`, checked white@16%).
- **`Theme.PillButton`** — JVoice `DarkPrimaryButton` analog (white text, `#1FFFFFFF` fill, `#3DFFFFFF`
  border, r7, 11px semibold) for small in-card actions (Browse…, Change).

### Settings redesign (`Settings/SettingsWindow.xaml[.cs]`) — the headline

Replace the 3-tab `TabControl` with a **single scroll of `DarkSection` cards in a two-column masonry**
(~760px wide, `SizeToContent=Height`, `MaxHeight` clamped to work area, `CanMinimize`). Instant-apply and
shortcut-recording behavior are **unchanged**; only the presentation changes. Named controls keep their
names so `LoadGeneral`/`LoadRecording`/`Apply`/`BuildShortcutRows` keep working.

Card plan (all dots white):
- **Column 1** — *After Capture* (After-capture 4-segment; Image format PNG/JPG segment; "Play a sound on
  capture" switch) · *Overlay* (corner 4-segment TL/TR/BL/BR; auto-dismiss 3/6/10s segment) · *Pins*
  (corner-radius styled ComboBox; "Drop shadow" switch) · *History* ("Remember capture history" switch;
  limit 10/50/200 segment) · *Startup* ("Launch at login" switch).
- **Column 2** — *Save Location* (folder TextBox + Browse pill) · *Shortcuts* (code-built rows: action
  label + mono chip + Change/Clear, restyled) · *Recording* (format MP4/GIF segment; fps 30/60 segment;
  system-audio/mic/camera-bubble/click-highlight/keystroke switches; camera-size Small/Medium segment;
  countdown Off/3/5/10 segment).

Enum→segment conversions add RadioButton groups; `LoadGeneral`/`LoadRecording` set `IsChecked` and
`Apply` reads it (helper maps group↔enum). Booleans stay `CheckBox` controls (with `Theme.MonoSwitch`
style) wired to the same `Changed` handler. `_loading` guard prevents write-back during load.

`UiPreview.cs`: the `shortcuts` case no longer sets `Tabs.SelectedIndex` (tabs are gone); it just opens
Settings (the Shortcuts card is in the same scroll).

### Other surfaces (mostly auto-propagate via tokens)

Manual literal fixes (the only remaining blues / for cohesion):
- `Editor/EditorWindow.xaml.cs:395,398` — selection marquee blue → white (`#FFFFFF` stroke, `#22FFFFFF` fill).
- `History/HistoryWindow.xaml.cs:34` — selected-cell border blue → white; nudge `CellBg`→`#161618`,
  `ThumbBg`→`#0E0E0E`.
- `Overlays/WindowPickerWindow.xaml.cs:35` — highlight blue → white.
- `Tray/DarkMenu.cs` — surface/hover/hairline toward black (`#141416` / `#242428` / `#2A2A2A`).
- **Left as-is (logged):** `Recording/ClickHighlighter.cs` `#2F6FEB` is a click ring **baked into the
  recorded video**, not app chrome; a white ring would be less legible over arbitrary content. Out of scope.
- `Branding/AppIconFactory.cs` (the product/tray icon, incl. the red record dot) — unchanged; it's the brand mark.
- Overlays (HUD, Selection, Countdown, Keystroke, CameraBubble, Pin) are already near-black + white-alpha —
  already on-language; spot-checked only.

## Verification

1. `dotnet build windows/BetterScreenshot.sln` — 0 errors/0 warnings.
2. `dotnet test windows/tests/BetterScreenshot.Tests` — all green (no logic touched; expect the existing baseline).
3. `pwsh windows/scripts/publish-app.ps1`, then launch the `dist` exe with
   `--ui-preview settings|shortcuts|editor|quickaccess|welcome|strip` and screenshot each
   (PowerShell `CopyFromScreen`). Inspect: pure-black surfaces, white glowing-dot cards, mono switches,
   segmented controls, **no white-on-white**, **no stray blue**.

## Decisions & assumptions (owner asleep)

1. **Windows-only** (see scope note). macOS app untouched.
2. **All section dots white** (uniform), faithful to JVoice's collapsed-to-white state — no per-section color.
3. **Destructive = monochrome** (no red button), matching JVoice; existing confirm dialogs remain the guard.
   The `Theme.DangerBrush` token is retained for the History "warn" badge only.
4. **Enum settings become segmented controls** where options are ≤4 short (pin-radius's 6 options stay a
   styled ComboBox). This is the biggest code-behind change; behavior (values written to `SettingsStore`)
   is identical and verified by build + preview.
5. **`ClickHighlighter` accent left blue** — it's a capture artifact, not chrome.
