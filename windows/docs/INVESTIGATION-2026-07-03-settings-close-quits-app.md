# Investigation — "closing Settings closes the whole app" (2026-07-03)

> Process log for an owner-reported issue in the WPF Windows port (`windows/`), written so a zero-context reader
> can follow the reasoning and reproduce the diagnostics. Fix landed in commit `5ab953c` on `windows-port`
> (`windows/src/BetterScreenshot.App/UiPreview.cs`). BetterScreenshot is a **menu-bar/tray agent**: it has no main
> window and is meant to stay resident until you Quit from the tray.

## The report

> "when you close the UI for BetterScreenshot, it closes the whole app… when you have settings open and you close
> it, it shouldn't close the full app, it should just close the settings."

Expected behaviour: closing the Settings window leaves the app running in the tray; only Quit (from the tray) exits.

## Methodology — reproduce before fixing

### Step 0 — read the shutdown model from source

`App.xaml` sets `ShutdownMode="OnExplicitShutdown"` — and has since the very first scaffold commit. In that mode a
WPF app shuts down **only** when `Application.Shutdown()` is explicitly called; closing any window does nothing to
process lifetime. A repo-wide grep for `Shutdown` / `Application.Current` / `MainWindow` / `.Close()` found the only
`Shutdown()` calls are the single-instance-mutex guard and the tray **Quit** command (`CaptureCoordinator` is
constructed with `Shutdown` as its quit callback). The tray "Settings…" item calls `commands.OpenSettings` →
`App.ShowSettings`, which just does `_settingsWindow.Show()`.

So **from source, closing Settings cannot quit the real app.** That contradicted the report — meaning the bug lived
somewhere the source read didn't obviously cover. Time to reproduce against a running process, not reason further.

### Step 1 — prove the real app on the owner's live process

A deployed instance was already running (`BetterScreenshot.App.exe` from `windows/dist/…`, the real tray agent),
with its Settings window open. Sent `WM_CLOSE` (`PostMessage 0x0010`) to that window's `HWND` and re-checked the
process:

```
Before: pid 12596, MainWindowTitle="BetterScreenshot Settings", handle=4130220
After : pid 12596 ALIVE, MainWindowTitle="", handle=0   (headless tray agent)
```

**The shipped tray agent does not have the bug.** Closing Settings left it resident with no window — exactly the
desired behaviour. (Closing the Settings window is harmless: settings are instant-apply, so nothing is lost.)

### Step 2 — find the one path that *does* quit

The only code that overrides the shutdown mode is the **dev UI gallery**, `UiPreview.Show`
(`BetterScreenshot.exe --ui-preview <name>`), which existed to screenshot a single themed window while a real
instance runs. It set:

```csharp
Application.Current.ShutdownMode = ShutdownMode.OnLastWindowClose;
```

Under `OnLastWindowClose`, closing the previewed **Settings** window closes the last window → the whole process
exits. Reproduced against a fresh `--ui-preview settings`:

```
After launch: alive, title="BetterScreenshot Settings"
After closing the settings window: PROCESS EXITED   ← the reported symptom
```

**Root cause:** the report was hitting the `--ui-preview` path — the natural way to eyeball the Settings UI (and
there was an in-progress Settings redesign at the time). That path ran under `OnLastWindowClose`, so "close Settings"
tore down the process. The shipped tray agent (`OnExplicitShutdown`) was already correct.

## The fix

Make `--ui-preview` **resident like the shipped app** instead of a throwaway single window
(`windows/src/BetterScreenshot.App/UiPreview.cs`):

- Keep `ShutdownMode.OnExplicitShutdown` (drop the `OnLastWindowClose` override).
- Create a real `TrayIcon` (the same one the app uses) backed by a small `PreviewCommands : IAppCommands`:
  - `OpenSettings()` opens/focuses the Settings window (so it can be reopened after closing).
  - `Quit()` calls `Application.Current.Shutdown()` — a clean way to exit (no orphan process).
  - capture/recording/history actions are no-ops (a static preview has no live pipeline).
- `Application.Current.Exit` disposes the tray icon so it doesn't ghost in the notification area.
- Still **no hotkeys and no single-instance mutex**, so the preview coexists with a live instance (its original
  purpose is preserved).

Now closing the previewed Settings window **returns to the tray**; reopen Settings or Quit from the tray icon —
mirroring the shipped agent.

## Verification

- `dotnet build …App.csproj -c Debug` → **0 warnings / 0 errors**.
- Ran the freshly built `--ui-preview settings`, sent `WM_CLOSE` to the window, re-checked the process:

  ```
  RESULT: PROCESS ALIVE after closing settings (FIXED) — now headless tray: title="", handle=0
  ```

  Before the fix the same test printed `PROCESS EXITED`.

**Repro for a human:** `dotnet run --project windows/src/BetterScreenshot.App -- --ui-preview settings` → close the
Settings window → the app stays in the tray (right-click the tray icon → Quit to exit).

## Notes / assumptions

- **The shipped tray agent needed no change** — it already keeps running when Settings closes (proven in Step 1).
  Only the `--ui-preview` dev path was fixed. If the app ever *appears* to close on the real agent, it's still
  running: Windows 11 hides new tray icons in the notification-area **overflow** (`^` chevron) by default — drag the
  camera icon out to keep it visible.
- A concurrent autonomous loop was editing this repo during the session. This fix was committed as **only**
  `UiPreview.cs` (commit `5ab953c`); no other in-flight WIP was staged or touched.
- `dist/` was **not** republished (the loop's WIP was mid-flight and a republish would require stopping the running
  instance). The real agent's behaviour is unchanged; a republish is only needed to test the fix via `--ui-preview`
  from the dist exe — run `pwsh windows/scripts/publish-app.ps1` once the tree settles.

## Methodology notes / lessons

- **When source says "impossible" but the user sees it, reproduce against the running process.** The source read
  (Step 0) correctly proved the *shipped* path was fine; only a live repro (Steps 1–2) located the actual culprit in
  a second, easy-to-overlook entry point (`--ui-preview`).
- **Enumerate every place that overrides the invariant.** The app's shutdown invariant (`OnExplicitShutdown`) was
  violated in exactly one spot; grepping for the override found it fast.
- **Fix the dev tool to match the product.** Rather than making the preview quit "more gracefully", it was made to
  behave like the real resident agent — so the preview is now a faithful stand-in and can't mislead again.
