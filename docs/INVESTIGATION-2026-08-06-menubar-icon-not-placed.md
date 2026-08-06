# Investigation — BetterScreenshot's menu-bar icon is never placed (2026-08-06)

**Status: RESOLVED (2026-08-06, same day, second session).** Root cause and fix are below; the
original investigation record follows unchanged for history.

## Root cause

macOS 26 (this machine: 26.5.2) moved all third-party menu-bar status items into **ControlCenter
hosting**: every visible status item is a window owned by the ControlCenter process (layer 25), and
an app's `NSStatusItem` only produces an on-screen icon if ControlCenter accepts ("tracks") the
app's *host* registration. ControlCenter also keeps an internal **blocked-host list** — the engine
behind System Settings → Menu Bar → "Allow in the Menu Bar" — and it held a stuck record keyed to
the bundle id `com.betterscreenshot.app`. Every launch, ControlCenter logged:

```
Moving host to blocked list; (bid:com.betterscreenshot.app-Item-0-<pid>)
Starting to track blocked host; …
```

(watch with `log stream --predicate 'process == "ControlCenter" AND category == "appStatusItems"'`).
A blocked host never gets a hosted window — which is exactly the "constructed correctly but never
placed" symptom recorded below. The record was **stuck**: the "BetterScreenshot" row in System
Settings → Menu Bar showed ON, and cycling it produced no ControlCenter reaction (dead row binding),
while the same toggle provably worked for a freshly-registered test app (blocked it, then
`Unblocking host` restored it live). "Reset Control Centre…" resets only Control Centre layout and
did not clear it. The record's backing store was never located — it is in none of: any `defaults`
domain (including ByHost and nested-binary-plist contents), `~/Library/Preferences`, ControlCenter's
Application Support / containers / group container, the LaunchServices database, or Screen Time
stores — and it survives `killall -9 ControlCenter` and logout.

**The matcher is the bundle id (with a valid code signature).** Bisected by launching copies of the
real app with exactly one identity field changed each: `CFBundleName` ✗ still blocked ·
`CFBundleExecutable` ✗ · bundle directory name ✗ · codesign `--identifier` ✗ · status-item
`autosaveName` ✗ (host id became `…-MainStatusItem` and was blocked anyway) · **`CFBundleIdentifier`
+ proper re-sign ✓ icon appears instantly**. (The "bundle identifier ruled out" row in the table
below was a false negative: that copy's Info.plist was edited without re-signing, so its effective
identity never changed.)

## Fix shipped

`App/Info.plist`: `CFBundleIdentifier` changed `com.betterscreenshot.app` → **`com.betterscreenshot.mac`**.
Do not revert it — the poisoned ControlCenter record for the old id cannot be deleted by any
supported means and will re-block the icon on this machine.

One-time migration done at deploy (2026-08-06):
- Settings copied to the new defaults domain: `defaults export com.betterscreenshot.app - | defaults import com.betterscreenshot.mac -`
  (capture history is unaffected — it lives at `~/Library/Application Support/BetterScreenshot/`, not keyed by bundle id).
- `didRegisterLaunchAtLogin` was deleted from the new domain so the app re-registered its login item.
- The Screen Recording permission does **not** follow a bundle-id change (macOS's TCC —
  Transparency, Consent, and Control — privacy database keys grants by bundle id), so the owner must
  re-grant it once via the app's onboarding window (Enable Screen Recording → toggle in System
  Settings → Privacy & Security → Screen & System Audio Recording).
- Investigation-era keys planted in the old `com.betterscreenshot.app` domain
  (`NSStatusItem VisibleCC Item-0`, `NSStatusItem Preferred Position Item-0`) are inert and were left.

Everything below is the original (pre-resolution) record.

---

## Context for someone with zero prior knowledge

BetterScreenshot is a free, local, macOS clone of CleanShot X (a screenshot + screen-recording tool),
written in Swift. It ships as `BetterScreenshot.app`, an `LSUIElement` menu-bar agent — meaning it has
no Dock icon, and its **only** user interface entry point is a status item (icon) in the macOS menu
bar at the top-right of the screen. That icon uses the SF Symbol `camera.viewfinder` and is created in
`App/MenuBar/MenuBarController.swift`.

**Symptom:** the icon does not appear in the menu bar. Because the app is `LSUIElement`, that makes
Settings, History, and every menu action unreachable by normal means.

## Environment where this reproduces

- MacBook Air, built-in display, **2560 x 1664 physical / 1470 x 956 logical points**, **has a notch**.
- Notch occupies x = 646 → 825. `NSScreen.auxiliaryTopRightArea` = `(825, 924, 645, 32)`, i.e. the
  right-hand status area is 645 points wide.
- Other menu-bar agents present and visible: Gloss (`G`), JVoice (`J`), MacStats (`~`), plus system
  items (AirPods, battery, Wi-Fi, Control Center, clock). These occupy roughly x = 1094 → 1470
  (~376 points), leaving ~269 points free.
- App bundle: `/Applications/BetterScreenshot.app`, bundle identifier `com.betterscreenshot.app`,
  signed with the local self-signed identity `BetterScreenshot Code Signing` created by
  `scripts/setup-signing.sh`.

## Established facts (each verified by direct test)

1. **The app is fully functional apart from the icon.** Its menu opens and works when invoked through
   the accessibility API:
   ```
   osascript -e 'tell application "System Events" to tell process "BetterScreenshot" to click menu bar item 1 of menu bar 1'
   ```
   This displays the real menu (Capture Area ⇧⌘4, Capture Window ⇧⌘8, Capture Fullscreen ⇧⌘7,
   Capture Text ⇧⌘6, Record Screen ⇧⌘5, Pin from Clipboard, History…, Restore Recently Closed,
   Settings… ⌘,, Quit ⌘Q). The global capture hotkeys also work normally.

2. **The status item is constructed correctly.** Instrumenting `MenuBarController.init` printed:
   ```
   button=ok  image=ok  visible=true  len=-1.0
   ```
   `len=-1.0` is not an error — `NSStatusItem.variableLength` is defined as `-1`. The button exists,
   its `NSImage(systemSymbolName: "camera.viewfinder", …)` loaded, and `isVisible` is `true`.

3. **macOS creates the item's window but never positions it in the menu bar.** The status item's
   backing window frame was sampled at launch and again 5 seconds later:
   ```
   window = (0.0, -6.0, 29.0, 22.0)
   ```
   The size (29–34 x 22–24) is correct for a status item; only the **origin** is wrong. A correctly
   placed item sits at roughly `(1045, 934)` on this screen.

4. **A control app CAN get a slot on the same machine at the same moment.** A throwaway ~10-line
   Swift app that does nothing but create an `NSStatusItem` was placed at `(1045, 4)` and its icon
   rendered immediately, both as a bare executable and wrapped in an `.app` bundle with
   `LSUIElement`. So the menu bar has room and accepts new items; BetterScreenshot specifically
   cannot get one.

5. **This is not caused by the v2.8.0 work** (refocus-after-capture + History multi-select, commits
   `70c82ab..7f89218`). The build at the immediately preceding commit `9faed03` was compiled in a
   separate git worktree and behaves **identically** — same missing icon, same `(0, -6)` origin.

6. **Skipping the screen-recording permission preflight changes the outcome.** In
   `App/Lifecycle/AppDelegate.swift`, `applicationDidFinishLaunching` calls
   `PermissionManager.hasScreenRecordingPermission`, which is `CGPreflightScreenCaptureAccess()`
   (see `App/SystemIntegration/PermissionManager.swift`). Guarding that call behind an environment
   variable and skipping it changed the item's window origin from `(0, -6)` (never placed) to
   `(1441, 934)` (placed on the menu-bar row, but at x=1441 on a 1470-wide screen, so clipped off the
   right edge behind the clock). **The icon is still not visible either way.** Permission is granted
   (`CGPreflightScreenCaptureAccess()` returns `true`), so the `if !hasPermission { … }` body never
   executes — the mere call is what matters. This is the single strongest lead and is *not* a fix.

## Ruled out — do not re-test these

Each was tested directly on the affected machine.

| Hypothesis | Result |
|---|---|
| Caused by the v2.8.0 change | No — pre-change build `9faed03` identical |
| Menu bar is full / overflow | No — ~269 points free; quitting MacStats to free a slot changed nothing |
| Log out and back in | No — owner logged out; `loginwindow` restarted 12:21; icon still absent |
| `killall SystemUIServer` | No effect |
| `killall ControlCenter` | No effect (re-ordered other icons, ours still absent) |
| `statusItem.autosaveName = "BetterScreenshot"` | No effect; never even persists a preference key |
| `com.apple.controlcenter` hidden-item keys | Nine `NSStatusItem Visible Item-N` keys are all `0`, alongside `HasAttemptedMenuBarWorkflowMigration = 1`. Flipping all nine to `true` + `killall ControlCenter` re-ordered other icons but ours stayed absent. **Values were restored to `0` afterwards.** |
| Stored preferred position | None exists for our item (`NSStatusItem Preferred Position *` keys exist only for Battery, BentoBox, FocusModes, ScreenMirroring, Sound, Timer, WiFi) |
| Code signature | Not it — an ad-hoc re-signed copy (`codesign --force --deep --sign -`) behaves identically |
| Entitlements | Not it — `App/BetterScreenshot.entitlements` is an empty dict; `codesign -d --entitlements -` confirms nothing on the binary |
| Bundle identifier | Not it — a copy with `CFBundleIdentifier` changed to `com.betterscreenshot.idtest` behaves identically |
| `LSUIElement` | Not it — the control app fails/succeeds the same with and without it |
| Bundle location | Not it — fails from `/Applications` and from `/private/tmp` alike |
| `Info.plist` contents | Nothing unusual; no `LSBackgroundOnly` |
| Duplicate LaunchServices registrations | Three registrations existed for `com.betterscreenshot.app` (`/Applications`, the repo's `dist/`, and a stale path whose bundle had been deleted). Reduced to exactly one with `lsregister -u` / `-f`. **No effect.** |
| `HotKeyManager` Carbon event handler | Not it — making it lazy so `InstallEventHandler`/`RegisterEventHotKey` never runs still leaves the item unplaced in a full launch |
| `SystemScreenshotShortcuts.disableNativeShortcuts()` (runs `activateSettings -u`) | Not it — skipping it changes nothing. Separately proven harmless: running `activateSettings -u` while the control app's icon was visible did **not** remove it |
| `OnboardingController` construction (creates an `NSWindow` with `defer: false`) | Not it — made lazy so it is never constructed; item still unplaced |
| Startup ordering generally | Not it — a status item created as the **first statement** of `applicationDidFinishLaunching`, before all other app code, is displaced too |

## How to reproduce the diagnostics

**Read the item's real geometry** (the accessibility API's `position` values are unreliable — they
returned `-1, 939`, `1437, -1` and `1440, -1` at various points; trust the window frame instead).
Add to `MenuBarController.init` after the image is set:

```swift
func diag(_ tag: String) {
    let b = statusItem.button
    FileHandle.standardError.write("DIAG[\(tag)] button=\(b == nil ? "NIL" : "ok") image=\(b?.image == nil ? "NIL" : "ok") visible=\(statusItem.isVisible) len=\(statusItem.length) frame=\(b?.frame ?? .zero) window=\(b?.window == nil ? "NIL" : "\(b!.window!.frame)")\n".data(using: .utf8)!)
}
diag("init")
DispatchQueue.main.asyncAfter(deadline: .now() + 5) { diag("t+5s") }
```

Then run the binary directly so stderr is visible (`open` swallows it):

```
/Applications/BetterScreenshot.app/Contents/MacOS/BetterScreenshot
```

**Screenshot the menu bar** (the only trustworthy check that the icon rendered):

```
screencapture -x -R0,0,1470,26 /tmp/menubar.png
```

**Screen geometry probe** used to rule out overflow — compile with `swiftc` and run:

```swift
import AppKit
for s in NSScreen.screens {
    print("frame: \(s.frame)")
    print("safeAreaInsets: \(s.safeAreaInsets)")
    print("auxiliaryTopLeftArea: \(String(describing: s.auxiliaryTopLeftArea))")
    print("auxiliaryTopRightArea: \(String(describing: s.auxiliaryTopRightArea))")
}
```

## Workarounds that work today

- All global capture hotkeys: **⌘⇧4** area, **⌘⇧8** window, **⌘⇧7** fullscreen, **⌘⇧6** text,
  **⌘⇧5** record.
- Settings / History via the accessibility click in fact 1 above.

## Leads not yet exhausted

1. **Why does the permission preflight matter?** `CGPreflightScreenCaptureAccess()` moves the item
   from "never placed" to "placed but clipped at the right edge". Understanding that is the most
   likely route to a real fix. Try deferring it well after launch, or off the main thread.
2. **Why x≈1437–1441 instead of the free slot at x≈1045?** Both of the app's status items (the real
   one and a debug second one) get parked at the extreme right edge, past the clock. Something is
   giving this process a right-most preferred position with no stored preference to explain it.
3. **A menu-bar manager** (for example Ice, free and open source) was never installed; it might
   surface the item and would also confirm whether the item is renderable at all.

## Related repo state discovered along the way

The macOS login item was launching `dist/BetterScreenshot.app` from the repo rather than
`/Applications/BetterScreenshot.app`, so the copy starting at login was whatever was last built in
the project folder. This is a separate problem from the icon; see the "deploy gap" note in the
project's memory. As of this investigation, LaunchServices holds a single registration pointing at
`/Applications/BetterScreenshot.app`, and that copy is byte-identical to a build of commit `7f89218`.
