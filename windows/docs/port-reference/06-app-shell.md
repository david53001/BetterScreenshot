# Port Reference — App shell (ground truth for the C#/.NET port)

Source = Swift `App/` (17 files). Target = `BetterScreenshot.App` (WPF, tray agent, no main window).
Ties everything together: tray menu, hotkeys, settings, onboarding, capture/recording orchestration.

## Shell / lifecycle
- **Tray agent, no taskbar/dock presence.** WPF: `App` with no `StartupUri`, no visible main window; `NotifyIcon`
  via `H.NotifyIcon.Wpf`. (mac: NSStatusBar + `.accessory` activation policy + LSUIElement.)
- Tray icon: **camera-viewfinder** glyph normally; **red stop** while recording, with elapsed **"H:MM:SS" / "M:SS"**
  monospaced text next to icon (tray tooltip on Windows, since tray can't show live text — show elapsed in tooltip + menu header).
- App bundle id `com.betterscreenshot.app`, name `BetterScreenshot`, version 2.4.0.

## Tray menu (exact items, order)
1. Capture Area — `captureArea`
2. Capture Window — `captureWindow`
3. Capture Fullscreen — `captureFullscreen`
4. Capture Text — `captureText`
--- sep ---
5. Record Screen…  (↔ "Stop Recording" while recording) — toggle
6. Pause Recording / Resume Recording (hidden unless recording/paused)
--- sep ---
7. Pin from Clipboard — `pinFromClipboard`
--- sep ---
8. History… — `openHistory`
9. Restore Recently Closed — `restoreRecentlyClosed`
--- sep ---
10. Settings… (show accel) 
11. Quit
Each item shows its hotkey text; refresh accelerators whenever a binding changes.

## Global hotkeys — WINDOWS default map (Cmd→Ctrl)
Win32 `RegisterHotKey(hwnd, id, MOD_CONTROL|MOD_SHIFT|MOD_NOREPEAT, vk)`:
| Action | Windows default | vk |
|---|---|---|
| captureArea | Ctrl+Shift+4 | 0x34 |
| captureWindow | Ctrl+Shift+8 | 0x38 |
| captureFullscreen | Ctrl+Shift+6 | 0x36 |
| captureText | Ctrl+Shift+7 | 0x37 |
| record | Ctrl+Shift+5 | 0x35 |
| pinFromClipboard | unbound | |
| openHistory | unbound | |
| restoreRecentlyClosed | unbound | |
| pauseResumeRecording | unbound | |
- Registration reports failures (combo owned by another app) → surface in Settings, track `failedActions`.
- `suspend()`/`resume()` around the shortcut-recorder field.
- **No native-shortcut suppression** (mac disabled ⌘⇧4/⌘⇧5; Windows has no equivalent registry of hotkeys — drop this; Ctrl+Shift+n don't collide with Windows defaults). Document in README.

## Settings store (→ JSON at %APPDATA%\BetterScreenshot\settings.json; keys 1:1 with mac UserDefaults)
| key | type | default |
|---|---|---|
| captureSettings | dict | CaptureSettings.default |
| saveDirectory | path | Windows `Pictures\Screenshots` (mac used com.apple.screencapture location / Desktop) |
| hotkeyBindings | dict | Windows defaults above |
| recordingConfig | dict | RecordingConfig.default |
| editorDefaultStyle | json | AnnotationStyle.default |
| didRegisterLaunchAtLogin | bool | false |
| RelaunchedAfterPermissionGrant | bool | false (mostly no-op on Windows) |
Recordings save to `Videos\` by default (mac used same screenshot dir). Use `Environment.SpecialFolder.MyPictures/MyVideos`.

## Settings UI (WPF, tabbed)
- **General**: after-capture behavior, format PNG/JPG (+JPG quality), overlay corner, auto-dismiss secs, save folder picker, pin radius/shadow, history enable/cap (10/50/200 — default 50; mac App text said 200 but CaptureKit default 50 — use **50**), launch-at-login, capture sound toggle.
- **Shortcuts**: one recorder row per action; click-to-record; captures only combos with Ctrl/Alt/Win (`.isValid`); Esc cancels, Backspace clears; conflict detection + error surface.
- **Recording**: format mp4/gif, fps 30/60, system audio, mic, camera + size, click highlights, keystroke overlay, countdown 0/3/5/10.
- Tabs icons: gearshape / keyboard / record.circle.

## Onboarding / first-run (WPF, 3 states — simplified for Windows)
- Windows has **no screen-recording permission gate**, so onboarding is a lightweight welcome (skip the permission poll/relaunch loop; keep a friendly first-run window).
- **welcome** state: app icon (72), "Welcome to BetterScreenshot", feature blurb, hotkey cheat sheet, "Start Capturing" button.
  Cheat sheet: Ctrl+Shift+4 area · Ctrl+Shift+5 record · Ctrl+Shift+6 fullscreen · Ctrl+Shift+8 window.
- Camera/mic: request via normal Windows APIs on first use (`MediaCapture` triggers the OS consent). No blocking gate needed.
- Show onboarding only on first run (persist a flag).

## Orchestration
- **CaptureCoordinator**: captureArea/Window/Fullscreen/Text → `handle(image, sourceRect)` routes by afterCapture
  (copyOnly/saveOnly/copyAndSave/showOverlay). showOverlay → Quick Access card (220×168, margin 24, bottom-right, stack ≤3).
  presentEditor wires onCopy/onSave/onAddToStack/onStyleChanged. keepInStack = history + overlay. pin/pinFromClipboard.
  copy = set clipboard bitmap + temp PNG file (5-min expiry). save = encode PNG/JPG to saveDirectory (create if missing).
- **RecordingCoordinator**: state machine, record strip, overlays, GIF convert, thumbnail→history→card. (see 05-recordingkit.md)
- **HistoryService**: facade over HistoryKit; recordScreenshot/recordRecording; restore-recently-closed LIFO;
  delete/clearAll; copyToClipboard; revealInExplorer (`explorer /select,`); thumbnail/image/savedFile getters.
- **RecordStripController**: floating strip: format mp4/gif, toggles mic/sysaudio/camera/clicks/keystrokes, target buttons (area/window/full), cancel.

## Windows/panels owned
Tray menu (always) · Settings window (lazy, reused, ~480 wide) · History window (lazy, 700×500 min 520×360, grid) ·
Onboarding (welcome) · Record strip (floating) · Pin panels (N) · Quick Access cards (≤3) · Editor window.

## App icon + branding (author natively)
- **App icon**: charcoal squircle bg **#1c1c1c** + white camera glyph (body 60%×40%, lens 27% Ø centered, viewfinder hump, flash window). Author as vector, render to multi-size `.ico` (16..256). (mac generated .icns from tools/make-icon.swift — reproduce the same look.)
- Info.plist usage strings map to nothing required on Windows (camera/mic consent handled by OS).

## Constants
QA margin 24 · onboarding welcome window ~440 wide · settings 480 · history 700×500 · record strip y=60 from top ·
accent = system accent (fallback #0A84FF-ish blue) · recording tint red · onboarding check green.

## No App-level unit tests (all tests live in the module libraries). App verified by running it.

## Icons used (author natively — see icons.md)
camera.viewfinder, stop.circle.fill, checkmark.circle.fill, camera, film, photo, exclamationmark.triangle,
gearshape, keyboard, record.circle, xmark.circle.fill, mic, speaker.wave.2, video.
