# Launch at Login — implementation note

The **Settings → Startup → "Launch at login"** toggle already existed in the UI and persisted to
`settings.json`, but it was a dead flag — nothing actually registered the app with Windows. This change wires
it to the per-user registry Run key (`HKCU\Software\Microsoft\Windows\CurrentVersion\Run`, value
`BetterScreenshot` = the quoted executable path) via `Platform/StartupRegistration.cs`. `SettingsWindow.Apply()`
reconciles the key the instant the toggle changes, and `App.OnStartup` reconciles it again on launch, so a
moved or republished build self-heals its path and a disabled flag never leaves a stale entry. The Run key was
chosen over a Startup-folder shortcut or Task Scheduler because it is per-user, needs no admin, is fully
reversible, and shows up in **Task Manager → Startup**. Verified with 7 unit tests against a throwaway registry
key plus an end-to-end check against the real Run key, then republished and relaunched the `dist/` tray agent.
