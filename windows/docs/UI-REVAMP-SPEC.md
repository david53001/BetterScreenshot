# Windows UI Revamp — Spec (2026-07-03)

## Context

The Windows port (`windows/`, .NET 9 + WPF, branch `windows-port`) is functionally complete but its
chrome-level UI still uses **default WPF control styling**: light-gray squared buttons with the classic
blue hover chrome, default TabControl/ComboBox/CheckBox visuals, light window backgrounds, and text-only
editor tool buttons. The macOS original (and its reference, CleanShot X) is a dark, rounded, icon-driven
UI. The owner reviewed the running app on 2026-07-03 and reported:

1. **No dark mode** — Settings and Welcome are light; everything should be dark.
2. **Looks "1990s", not macOS-like** — no rounded corners on controls, default WPF button chrome
   (squared light-blue hover boxes that visually collide with the thumbnail on the Quick Access card).
3. **Dragging the Quick Access thumbnail out does not dismiss the overlay** (on macOS drag-out ends the
   overlay).
4. **"Shortcuts don't save / settings don't save."**
5. **Editor tools are text labels** ("Select Arrow Line …") with no icons.
6. Rebound shortcut renders as **`Alt+(vk 190)`** instead of `Alt+.`.

### Root-cause findings (verified against live code + on-disk state)

- **Settings DO persist.** `%APPDATA%\BetterScreenshot\settings.json` contains the owner's rebind
  (`"CaptureArea": "190,1"` = Alt+OEM_PERIOD). The *perception* of loss has two real causes:
  - `SettingsWindow` uses a **Save/Cancel model**; `OnClosed` reverts all hotkey changes unless the
    `Save` button was clicked (`SettingsWindow.xaml.cs:224-229`). Closing via the title-bar ✕ — the
    natural Windows gesture — silently discards every change. That *is* "settings don't save".
  - `HotkeyCombo.KeyName` (`windows/src/BetterScreenshot.Capture/Hotkeys.cs:94`) has no mapping for
    OEM virtual keys, so `.` renders as `(vk 190)` — which reads as a corrupted/unsaved value.
- **Quick Access drag**: `QuickAccessWindow.Thumb_MouseMove` starts `DragDrop.DoDragDrop` but never
  dismisses afterwards (`QuickAccessWindow.xaml.cs:68-77`).
- **Editor toolbar**: `EditorWindow.BuildToolbar` creates `Button { Content = label }` text buttons even
  though hand-authored glyphs for **every** tool already exist in `Resources/Icons.xaml`
  (`icon-cursor`, `icon-arrow`, `icon-line`, `icon-rect`, `icon-rect-fill`, `icon-ellipse`, `icon-text`,
  `icon-counter`, `icon-blur`, `icon-pixelate`, `icon-crop`) with the `IconPresenter` control
  (`windows/src/BetterScreenshot.App/Controls/IconPresenter.cs`) already rendering them elsewhere.
- **No app-wide theme**: `App.xaml` merges only `Resources/Icons.xaml`. Every control renders with
  default WPF chrome. Quick Access / RecordStrip cards are hardcoded **light** (`#FFFAFAFC`), and their
  glyph brushes are dark (`#333333`).
- **Stale tray shortcuts**: `TrayIcon` captures `HotkeyBindings` once at construction; menu shortcut
  text never updates after a rebind.

## Goal / "done" looks like

A single coherent **dark, macOS-inspired** visual system across every window, matching the macOS
original's character: dark surfaces, 10%-white hairline borders, rounded (6–12 px) controls, restrained
`#0A84FF` accent, icon-driven toolbars — plus the three behavioral fixes (instant-apply settings,
readable key names, drag-out dismisses the overlay). Build clean (0 warnings-as-errors), all pure-logic
tests green, and visual verification via screenshots of the running windows.

## Design tokens (Theme.xaml)

The brief is fidelity to the macOS app, so tokens derive from the macOS dark HIG rather than a novel
identity. All defined once in `windows/src/BetterScreenshot.App/Resources/Theme.xaml`:

| Token (x:Key)            | Value       | Use |
|--------------------------|-------------|-----|
| `Theme.WindowBrush`      | `#232326`   | Window backgrounds (matches existing editor `#2B2B2E` family, slightly deepened) |
| `Theme.ChromeBrush`      | `#1C1C1F`   | Top/bottom bars, footers |
| `Theme.CardBrush`        | `#2C2C30`   | Floating cards (Quick Access, record strip), popups |
| `Theme.ControlBrush`     | `#3A3A3F`   | Resting fill for buttons/inputs |
| `Theme.ControlHoverBrush`| `#47474D`   | Hover fill |
| `Theme.ControlPressedBrush`| `#525259` | Pressed fill |
| `Theme.SubtleHoverBrush` | `#1AFFFFFF` | Hover for transparent icon buttons |
| `Theme.SubtlePressedBrush`| `#2BFFFFFF`| Pressed for transparent icon buttons |
| `Theme.BorderBrush`      | `#26FFFFFF` | Hairlines (15% white) |
| `Theme.TextBrush`        | `#F2F2F5`   | Primary text |
| `Theme.SecondaryTextBrush`| `#9A9AA2`  | Secondary text, labels |
| `Theme.AccentBrush`      | `#0A84FF`   | Accent (already the app accent) |
| `Theme.AccentHoverBrush` | `#2B94FF`   | Accent hover |
| `Theme.AccentPressedBrush`| `#0870DB`  | Accent pressed |
| `Theme.DangerBrush`      | `#FF453A`   | Destructive (Delete/Clear All) |

Type: Segoe UI throughout (13 px body); **Cascadia Mono, Consolas fallback** for shortcut chips.
Radii: 6 px controls · 8 px inputs/popups · 12 px floating cards (matches existing card radius).

### Implicit styles (restyle-by-default)

`Theme.xaml` defines **implicit styles with full ControlTemplates** so the 90s chrome disappears
everywhere without touching every call site:

- `Button` — rounded 6, `ControlBrush` fill, hover/pressed triggers, `IsEnabled=False` → 40 % opacity.
  Keyed variants: `Theme.AccentButton` (blue/white), `Theme.SubtleButton` (transparent, rounded hover —
  for icon-only buttons), `Theme.DangerButton` (for Delete/Clear All).
- `ToggleButton` — like Button; `IsChecked` → accent fill, white content.
- `ComboBox` + `ComboBoxItem` — full template: rounded field, hand-drawn chevron `Path`, dark rounded
  popup with hairline border; item hover = `SubtleHoverBrush`, selected = accent.
- `CheckBox` — 16 px rounded-4 box, accent fill + white check `Path` when checked.
- `TextBox` — dark fill, rounded 6, hairline border, accent border on keyboard focus.
- `TabControl`/`TabItem` — macOS segmented style: centered pill row on a `#1AFFFFFF` track; selected
  segment = `ControlBrush` pill with primary text; unselected = transparent with secondary text.
- `ScrollBar` — slim (8 px), no arrows, rounded `#33FFFFFF` thumb.
- `ToolTip` — `CardBrush`, rounded 6, hairline border.
- `Window` gets **no** implicit style (WPF doesn't apply implicit Window styles from App.xaml reliably);
  instead each titled window sets `Background={StaticResource Theme.WindowBrush}` and calls the helper
  below.

### Dark title bars

New `windows/src/BetterScreenshot.App/Controls/WindowThemer.cs`:
`WindowThemer.ApplyDark(Window)` P/Invokes `DwmSetWindowAttribute(DWMWA_USE_IMMERSIVE_DARK_MODE = 20)`
on `SourceInitialized` (falls back silently on failure). Applied to the four titled windows: Settings,
Editor, History, Welcome. Win11 already rounds top-level window corners; no extra work.

## Per-surface changes

### 1. Settings window (`Settings/SettingsWindow.xaml[.cs]`) — instant apply + restyle
- **Remove Save/Cancel entirely.** Every control persists on change (`_settings.…= …; _settings.Save()`)
  — the macOS-idiomatic model and the root-cause fix for "settings don't save". Closing with ✕ keeps
  changes. Remove `_hotkeySnapshot`/revert logic; `OnClosed` only calls `_hotkeys.Apply`.
- Hotkey rebind/clear: persist + `_hotkeys.Apply` immediately; raise `HotkeysChanged` so `App` can call
  the new `TrayIcon.UpdateShortcuts(HotkeyBindings)` (fixes stale tray menu text).
- Restyle: dark window, segmented tabs, aligned rows (label column 170 px, secondary-text labels),
  shortcut combos shown as **mono chips** (rounded `ControlBrush` border), `Change` becomes a subtle
  button that turns into an accent "Press keys… (Esc cancels)" state while recording; `Clear` becomes a
  subtle ✕ icon button.
- Recording-conflict + folder-picker flows unchanged.

### 2. Hotkey key names (`Capture/Hotkeys.cs` + tests) 
Extend `HotkeyCombo.KeyName` with the OEM/navigation VKs (US-layout labels, matching how the recorder
stores them): `0xBA ;` `0xBB =` `0xBC ,` `0xBD -` `0xBE .` `0xBF /` `0xC0 ` `` ` `` `0xDB [` `0xDC \`
`0xDD ]` `0xDE '` plus `0x2D Ins` `0x2E Del` `0x21 PgUp` `0x22 PgDn` `0x23 End` `0x24 Home`
`0x13 Pause` `0x2C PrtSc`, numpad `0x60–0x69` → `Num0–Num9`, `0x6A * 0x6B + 0x6D − 0x6E . 0x6F /`.
TDD in `windows/tests/BetterScreenshot.Tests/HotkeyTests.cs` (e.g. `(190,Alt)` → `"Alt+."`).

### 3. Quick Access card (`Overlays/QuickAccessWindow.xaml[.cs]`)
- Card → `CardBrush` + hairline border (radius 12 kept); thumbnail well → `#14FFFFFF`; recording variant
  uses the same dark card (kind only changes the button set).
- Buttons use `Theme.SubtleButton` (rounded hover instead of the blue square); `GlyphBrush` → `#F2F2F5`.
- **Drag-out dismiss**: after `DragDrop.DoDragDrop` returns with any effect other than `None`, call
  `Dismiss(DismissReason.ActionTaken)` (Esc-cancelled drags keep the card).

### 4. Editor (`Editor/EditorWindow.xaml[.cs]`)
- **Toolbar → icon ToggleButtons** using the existing `Icons.xaml` glyphs + `IconPresenter`, one per
  tool, tooltips with the tool name, radio behavior (checked = accent fill + white glyph). Selected
  state tracked in `_toolButtons`; `Select` checked initially.
- Inspector: color swatches become **round** 20 px buttons with a 2 px white ring on the active color;
  weight buttons show filled dots (small/medium/large) instead of "2/4/7"; font-size buttons show
  "A" at three sizes; the active weight/size gets the ring/accent state; initial state reflects the
  sticky `_style`.
- Bottom bar: theme buttons; `Copy` uses `Theme.AccentButton`.
- Window: dark title bar (background already dark).

### 5. Remaining surfaces
- **Welcome** (`Onboarding/WelcomeWindow.xaml`): dark window + title bar, light text, `#14FFFFFF`
  hotkey panel with mono chips, accent Start button. Keep the app-icon vignette.
- **History** (`History/HistoryWindow.xaml[.cs]`): buttons inherit theme automatically; `Delete`/
  `Clear All…` use `Theme.DangerButton`; dark title bar. Grid cells already dark.
- **Record strip** (`Recording/RecordStripWindow.xaml[.cs]`): card → `CardBrush` + hairline; glyph
  off-state → `#C8C8CF`; separators → `#26FFFFFF`; segment accent → `Theme.AccentBrush` (`#0A84FF`,
  replacing the odd `#2F6FEB`); text/segment buttons pick up theme styles.
- **Tray menu** (`Tray/TrayIcon.cs` + new `Tray/DarkMenu.cs`): WinForms `ContextMenuStrip` gets a dark
  `ToolStripProfessionalRenderer` (custom `ProfessionalColorTable`: `#2C2C30` surface, `#3A3A3F`
  highlight, light text) so the tray menu matches. Add `UpdateShortcuts(HotkeyBindings)`.
- Already-dark overlays (HUD, Pin, WindowPicker, Selection, Countdown, Keystroke, CameraBubble):
  unchanged apart from spot-check.

### 6. Dev preview flag (verification vehicle)
`App.OnStartup`: when launched with `--ui-preview <settings|editor|quickaccess|welcome|history|strip>`,
skip the single-instance mutex/tray/hotkeys and open just that window with sample data (generated
gradient bitmap for editor/quick-access). Lets an agent screenshot each surface without driving the
tray UI, and coexists with a running real instance. Documented in PROGRESS.md; harmless in production
(flag-gated).

## Explicitly out of scope
- Light mode / system-theme following — the owner asked for dark ("It should all be dark").
- Restyling system `MessageBox`es and the WinForms folder picker (native dialogs; follow OS theme).
- The in-canvas text-annotation `TextBox` look (functional; sits on the image, not chrome).
- Any capture/recording behavior changes.

## Decisions & assumptions (owner asleep — logged per global CLAUDE.md)
1. **Instant-apply replaces Save/Cancel** — interpreted "settings don't save" as the ✕-close revert
   trap (evidence: the file on disk *does* contain the rebind). Instant-apply is also what CleanShot X
   does. If explicit Save is preferred, the change is isolated to `SettingsWindow`.
2. **Always-dark** (no theme toggle), per the owner's words. Tokens centralised so a light map could be
   added later.
3. **US-layout labels for OEM keys** (static, testable). A `MapVirtualKeyW` per-layout lookup could
   replace it later; out of scope now.
4. Tray menu goes dark via a custom renderer rather than being left native-light, to honor "it should
   all be dark".
5. `--ui-preview` ships in the app (flag-gated) as the permanent visual-verification hook.

## Verification
1. `dotnet build windows/BetterScreenshot.sln` (or the App csproj) — 0 errors.
2. `dotnet test windows/tests/BetterScreenshot.Tests` — all green (baseline 214 + new KeyName cases).
3. `windows/scripts/publish-app.ps1` → launch `dist` exe with `--ui-preview settings` etc.; screenshot
   each window (PowerShell `CopyFromScreen`) and inspect: dark surfaces, rounded hover, icon toolbar,
   readable `Alt+.` chip.
4. Manual behavioral checks: rebind a hotkey → close window with ✕ → reopen (persisted); drag the Quick
   Access thumbnail into Explorer (card dismisses); Esc during drag (card stays).
