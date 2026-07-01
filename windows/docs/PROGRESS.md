# BetterScreenshot-Windows — Progress Ledger

The loop (`windows/LOOP-PROMPT.md`) reads this first every firing to avoid redoing work. Keep it current: check off
finished tasks, move the pointer, log assumptions/known-issues. One firing = one durable increment.

## Current pointer
- **Branch:** `windows-port`
- **Phase:** Phase 0 (scaffold) — being set up in the seeding session.
- **Next task:** whatever is the first unchecked task in `PLAN.md` when you read it. If Phase 0 tasks are already
  done and green, proceed to Phase 1 Task 1.1.

## Status snapshot (update every firing)
- Build: (run `dotnet build windows/BetterScreenshot.sln -c Release` and record pass/fail)
- Tests: (run `dotnet test windows/tests/BetterScreenshot.Tests -c Release` and record count/pass-fail)

## Completed (append as you go)
- 2026-07-01 (seed): Reconnaissance of the macOS app; wrote SPEC.md, PLAN.md, LOOP-PROMPT.md, and the seven
  `port-reference/*.md` ground-truth docs. Stack decided: .NET 9 + WPF, ffmpeg for recording. Validated a clean
  WPF+WinRT build on this machine.

## Assumptions log (decisions made without asking; David can review)
- Windows hotkeys map Cmd→Ctrl: Ctrl+Shift+4/5/6/7/8 (SPEC §4).
- macOS screen-recording permission flow + native-shortcut suppression are **dropped** (no Windows equivalent needed).
- Recording engine = ffmpeg (DXGI/gdigrab + WASAPI loopback + dshow), not a custom encoder.
- History cap default = 50 (CaptureKit default; the mac App note said 200 — using 50 per the tested default).
- Save destinations default to `Pictures\Screenshots` (images) and `Videos\` (recordings).

## Known issues / TODO discovered during build (append as you find them)
- (none yet)
