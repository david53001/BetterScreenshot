# App/Lifecycle — app entry & wiring

Bootstrap and lifecycle for the menu-bar agent.

- `Main.swift` — process entry; creates the `NSApplication` and installs `AppDelegate`.
- `AppDelegate.swift` — owns and wires the app's coordinators (capture, recording, history),
  registers global hotkeys, and runs terminate/cleanup hooks (e.g. restoring native screenshot
  shortcuts on quit).

These files are the glue layer: they instantiate the controllers defined in the sibling `App/*`
sections and connect them to the `Packages/*` modules. Behavior change here affects startup and
shutdown ordering — verify by launching `dist/BetterScreenshot.app` after `scripts/build-app.sh`.
