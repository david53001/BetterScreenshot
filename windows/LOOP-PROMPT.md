# BetterScreenshot-Windows — Autonomous Build/Harden Loop Prompt

You are a fresh Claude Code session with **zero prior context**, fired by `/loop` on an interval. Do exactly one
durable increment of work on the **Windows port of BetterScreenshot**, leave the repo green and committed, then
report the delta. Everything you need is on disk — read it; do not rely on memory of past firings.

## 1. Run mode
Work **unattended and autonomously**. The user (David) is asleep and cannot answer. **Never ask questions** — when
something is ambiguous, pick the most reasonable interpretation consistent with the reference docs, write it in the
progress ledger as an assumption, and proceed. Keep momentum. **Only stop and write a clear blocking note** if you
hit a true hard stop: about to do something destructive/irreversible you can't undo, something that spends real
money, or you are genuinely blocked on every interpretation. Otherwise, keep building.

## 2. Read first (in this order, before touching anything)
Repo root: `C:\Users\david_v0a3rlc\Sorted\Coding\Apps\BetterScreenshot`. Branch: **`windows-port`**.
1. `windows/docs/PROGRESS.md` — the ledger: what previous firings finished, current phase/task, logged assumptions/known issues. **This is how you avoid redoing work.**
2. `windows/docs/PLAN.md` — the full phased task list (checkboxes). Your worklist.
3. `windows/docs/SPEC.md` — design decisions and acceptance criteria.
4. The `windows/docs/port-reference/NN-*.md` doc(s) for the module you're about to touch — these hold the exact
   constants, signatures, and test assertions to match. They are the authoritative fidelity spec.
5. Only if you need original behavior detail: the Swift source under `App/` and `Packages/` (the reference app).

## 3. Goal + definition of done
**Goal:** make the Windows app a faithful, working duplicate of the macOS BetterScreenshot app, per PLAN.md.
**Done (the stop condition):** every PLAN.md task checkbox is checked AND `dotnet build` is clean AND
`dotnet test` is fully green AND the Verification Checklist (PLAN.md §V) all passes AND a full re-scan this firing
surfaces no new correctness/fidelity issue. When all of that holds, write `DONE — nothing left` in PROGRESS.md and
report it; make no further code changes.

## 4. Steps (do them in order; stop after one durable increment)
1. **Re-assess state.** Read PROGRESS.md. Then run, from the repo root:
   - `dotnet build windows/BetterScreenshot.sln -c Release`
   - `dotnet test windows/tests/BetterScreenshot.Tests -c Release`
   If either fails, **fixing that is this firing's increment** — it takes priority over new features. Diagnose the
   root cause (use superpowers:systematic-debugging), fix, re-run until green, commit, update ledger, report. Done.
2. **If build+tests are green but PLAN has unchecked tasks:** take the **next single unchecked task** in PLAN order.
   Implement it with TDD where it's pure logic (write the failing xUnit test from the reference doc's assertions →
   run red → implement → run green). For UI/system tasks, implement the smallest coherent unit and verify by
   building (and running the app if the change is observable). Check the task's box in PLAN.md. Commit
   (Conventional Commit). Update PROGRESS.md (task done, phase, any assumption). Report the delta. Done.
3. **If all PLAN tasks are checked:** switch to **harden mode**. Run the full Verification Checklist (PLAN.md §V).
   Pick the single most important issue found — a failing check, a fidelity gap vs a reference-doc constant, a
   crash, a missing behavior, a placeholder icon, an unhandled error, a leaked temp file, a DPI bug — reproduce it,
   fix the root cause, add/adjust a test if it's testable, verify, commit, log it in PROGRESS.md, report. One issue
   per firing.
4. **If harden mode finds nothing** after a genuine end-to-end pass: write `DONE — nothing left` in PROGRESS.md and
   report it. Make no changes.

Optional/stretch (only after §V is fully green and only if nothing above remains): the trim editor (SPEC §7),
packaging/installer, extra polish. Mark these clearly as stretch in the ledger.

## 5. Rules (hold these no matter what)
- **Git:** stay on branch `windows-port`. Commit after each task/fix with a clear Conventional Commit message.
  **Never push, never open PRs, never force-push.** Prefer `git add <specific paths>` over `git add -A`.
- **End green.** Never end a firing with a broken build or red tests. If you can't finish an increment cleanly,
  revert your partial change so the next firing starts clean, and log why.
- **TDD for pure logic.** All pure-logic behavior (geometry, model, config, state, timing, history, redaction) is
  test-first, and must keep every ported macOS test suite green. Do not weaken/skip/delete a test to make it pass —
  fix the code.
- **Fidelity over invention.** Match the constants/behaviors/test-assertions in the `port-reference/*.md` docs
  exactly. Coordinates are **top-left** on Windows (no Cocoa Y-flips). If a doc and the Swift source disagree, the
  Swift source wins — note the discrepancy in the ledger.
- **All icons/art are hand-authored vector geometry** (`port-reference/07-icons.md`). Never embed a screenshot or
  cropped image of the original app.
- **100% local.** No network calls, ever (no HttpClient/WebClient/Socket/update-check). If you add a dependency,
  it must be OSS and offline. Recording uses the installed **ffmpeg** (PATH or `windows/tools/ffmpeg.exe`).
- **Honesty.** Report what actually happened. If a check failed or a step was skipped, say so with the evidence.
  Never claim done on assumption — run the command and read the output.
- **Toolchain:** .NET 9 SDK (`dotnet` on PATH). App/Platform target `net9.0-windows10.0.19041.0`; pure libs `net9.0`.
  Build the whole solution and run `dotnet test` before committing.

## 6. When done (each firing)
- Update `windows/docs/PROGRESS.md`: check off what you finished, set the current phase/task pointer, append any
  assumption or known issue, and (if applicable) the `DONE — nothing left` line.
- Ensure PLAN.md checkboxes reflect reality.
- Report back a short delta: **what this firing changed**, **what remains**, and **anything needing David's eyes**.
