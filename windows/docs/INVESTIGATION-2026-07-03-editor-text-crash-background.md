# Investigation — editor text crash on click-off + white text background (2026-07-03)

> Owner-reported, WPF Windows port (`windows/`). Fix landed in commit `dc8c9a2` on `windows-port`.
> Files: `Editor/EditorWindow.xaml.cs`, `Editor/DocumentRenderer.cs`, `BetterScreenshot.Editor/EditorStyle.cs`,
> plus tests. Written in short sentences.

## The report

- Take a screenshot. Add text. Click off the text back onto the image. The whole app crashes.
- Also: the text is clunky and has a white background. It should have no background by default, with an option to add one.

## Bug 1 — the crash

- Reproduced end-to-end with a temporary self-driving `--ui-preview` harness.
- Exact exception: `NullReferenceException` in `PlaceTextBox`, called from `OnDown`.
- There is no global exception handler, so an unhandled handler exception kills the whole process.

### Root cause

- Every editing `TextBox` had `LostKeyboardFocus += CommitText()`.
- `CommitText()` committed whatever the shared `_textBox` field pointed at — not the box that lost focus.
- On click-off, `OnDown` committed the old box, then immediately placed a new box in the same handler.
- A late-firing `LostKeyboardFocus` from the just-removed box then re-entered `CommitText()`.
- That nulled `_textBox` midway through `PlaceTextBox`, so the next line dereferenced null.

### Fix (defense in depth)

- `CommitText(TextBox box)` now bails unless `ReferenceEquals(box, _textBox)`. A stale/late focus event is ignored.
- Handlers are wired to *that specific box*, and attached *before* `Focus()`.
- `OnDown` now treats a click while editing as "finish this text and consume the click." It no longer commits-then-places a new box in one click. That also removes the clunky auto re-placement.

## Bug 2 — white text background

- The inline editor was a fully themed white `TextBox`. Typing looked nothing like the flattened result.
- The editing box is now WYSIWYG: transparent, no border/chrome, stroke-colored bold text in the render font.
- Text now has **no background by default**.
- A new inspector toggle (rightmost button) adds an optional rounded "label" chip behind the text.
- The chip color is auto-picked for contrast: dark chip behind light text, light chip behind dark text.
- The choice is sticky (persisted in `AnnotationStyle.TextBackground`) and drawn by `DocumentRenderer`.
- Old persisted styles without the field load fine (field absent → `null` → no background).

## Verification

- Build clean (0/0). Full suite **260 green** (5 new: style back-compat + chip render).
- Crash harness now survives every ordering: place→click-off, Enter-commit, focus-first, and rapid multi-box.
- Visually confirmed via `PrintWindow` capture: no white box; red text with no background; yellow-on-dark chip; transparent live editing box.
- `dist/` republished (Release) and smoke-tested — the editor launches cleanly.

## Notes

- A concurrent autonomous agent was editing this repo during the session (owner's InfoTip/TempFiles work).
  My fix touched only the 5 files above and was rebased cleanly on top of their commit `3e6edea`. Their work was untouched.
- Optional background is a single on/off toggle with an auto-contrast color, not a full color picker. A pickable chip color would be a small follow-on.
