# App/MenuBar — status-item menu & onboarding

- `MenuBarController.swift` — the `NSStatusItem` menu bar item: builds the menu (capture/record/history
  items), reflects recording state + elapsed-time in the icon, and adopts `NSMenuItemValidation`.
- `OnboardingController.swift` — first-run onboarding flow, including prompting for the Screen Recording
  permission (works with `App/SystemIntegration/PermissionManager`).

This is the app's primary always-on UI entry point. Verify by launching the built app and exercising
the menu.
