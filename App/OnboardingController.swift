import AppKit

/// First-run setup window. The app needs exactly one permission — Screen
/// Recording — and a grant only takes effect after a relaunch. This window
/// collapses that dance into a single button: request → System Settings opens
/// at the right pane → poll until the switch flips → relaunch automatically →
/// confirm with a hotkey cheat-sheet.
@MainActor
final class OnboardingController: NSWindowController {
    enum State { case needsPermission, waiting, allSet }

    private static let relaunchFlagKey = "RelaunchedAfterPermissionGrant"

    /// True exactly once: on the launch right after the permission relaunch.
    static func consumeRelaunchFlag() -> Bool {
        let defaults = UserDefaults.standard
        guard defaults.bool(forKey: relaunchFlagKey) else { return false }
        defaults.removeObject(forKey: relaunchFlagKey)
        return true
    }

    private var pollTimer: Timer?

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 100),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered, defer: false)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isReleasedWhenClosed = false
        super.init(window: window)
    }
    required init?(coder: NSCoder) { fatalError() }

    func show(_ state: State) {
        render(state)
        window?.center()
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        // Poll from the moment the window is up, so even a user who flips the
        // switch on their own (without our button) gets the auto-relaunch.
        if state != .allSet { startPolling() }
    }

    // MARK: - States

    private func render(_ state: State) {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: 38, left: 36, bottom: 28, right: 36)
        stack.translatesAutoresizingMaskIntoConstraints = false

        switch state {
        case .needsPermission:
            stack.addArrangedSubview(appIconView())
            stack.addArrangedSubview(titleLabel("Welcome to BetterScreenshot"))
            stack.addArrangedSubview(bodyLabel(
                "Capture, annotate, and share screenshots — right from your menu bar."))
            stack.setCustomSpacing(22, after: stack.arrangedSubviews.last!)
            stack.addArrangedSubview(bodyLabel(
                "macOS asks for one permission: Screen Recording. Click the button, "
                + "turn on BetterScreenshot in System Settings, and the app will "
                + "restart itself — that's it."))
            stack.setCustomSpacing(18, after: stack.arrangedSubviews.last!)
            stack.addArrangedSubview(primaryButton("Enable Screen Recording",
                                                   action: #selector(enableTapped)))
        case .waiting:
            stack.addArrangedSubview(appIconView())
            stack.addArrangedSubview(titleLabel("Waiting for permission…"))
            let spinner = NSProgressIndicator()
            spinner.style = .spinning
            spinner.controlSize = .small
            spinner.startAnimation(nil)
            stack.addArrangedSubview(spinner)
            stack.addArrangedSubview(bodyLabel(
                "In System Settings → Privacy & Security → Screen Recording, "
                + "turn on BetterScreenshot.\nThe app restarts automatically "
                + "the moment it's enabled."))
        case .allSet:
            let check = NSImageView()
            check.image = NSImage(systemSymbolName: "checkmark.circle.fill",
                                  accessibilityDescription: "Ready")?
                .withSymbolConfiguration(.init(pointSize: 50, weight: .regular))
            check.contentTintColor = .systemGreen
            stack.addArrangedSubview(check)
            stack.addArrangedSubview(titleLabel("You're all set!"))
            stack.addArrangedSubview(bodyLabel(
                "BetterScreenshot lives in your menu bar. Capture any time with:"))
            stack.setCustomSpacing(14, after: stack.arrangedSubviews.last!)
            stack.addArrangedSubview(hotkeyRow("⌘⇧4", "Capture an area"))
            stack.addArrangedSubview(hotkeyRow("⌘⇧5", "Record the screen"))
            stack.addArrangedSubview(hotkeyRow("⌘⇧6", "Capture the full screen"))
            stack.addArrangedSubview(hotkeyRow("⌘⇧8", "Capture a window"))
            stack.setCustomSpacing(18, after: stack.arrangedSubviews.last!)
            stack.addArrangedSubview(primaryButton("Start Capturing",
                                                   action: #selector(startCapturing)))
        }

        let content = NSView()
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: content.topAnchor),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            content.widthAnchor.constraint(equalToConstant: 440),
        ])
        window?.contentView = content
        window?.setContentSize(content.fittingSize)
    }

    // MARK: - Pieces

    private func appIconView() -> NSImageView {
        let v = NSImageView()
        v.image = NSApp.applicationIconImage
        v.imageScaling = .scaleProportionallyUpOrDown
        v.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            v.widthAnchor.constraint(equalToConstant: 72),
            v.heightAnchor.constraint(equalToConstant: 72),
        ])
        return v
    }

    private func titleLabel(_ text: String) -> NSTextField {
        let l = NSTextField(labelWithString: text)
        l.font = .systemFont(ofSize: 19, weight: .bold)
        l.alignment = .center
        return l
    }

    private func bodyLabel(_ text: String) -> NSTextField {
        let l = NSTextField(wrappingLabelWithString: text)
        l.font = .systemFont(ofSize: 13)
        l.textColor = .secondaryLabelColor
        l.alignment = .center
        l.preferredMaxLayoutWidth = 360
        return l
    }

    private func primaryButton(_ title: String, action: Selector) -> NSButton {
        let b = NSButton(title: title, target: self, action: action)
        b.bezelStyle = .rounded
        b.controlSize = .large
        b.keyEquivalent = "\r"
        return b
    }

    private func hotkeyRow(_ keys: String, _ name: String) -> NSStackView {
        let keyLabel = NSTextField(labelWithString: keys)
        keyLabel.font = .monospacedSystemFont(ofSize: 13, weight: .semibold)
        keyLabel.translatesAutoresizingMaskIntoConstraints = false
        keyLabel.widthAnchor.constraint(equalToConstant: 52).isActive = true
        let nameLabel = NSTextField(labelWithString: name)
        nameLabel.font = .systemFont(ofSize: 13)
        nameLabel.textColor = .secondaryLabelColor
        let row = NSStackView(views: [keyLabel, nameLabel])
        row.orientation = .horizontal
        row.spacing = 10
        return row
    }

    // MARK: - Actions

    @objc private func enableTapped() {
        PermissionManager.requestScreenRecordingPermission()
        // Give the system prompt a beat to appear, then open the exact pane
        // behind it (covers the case where the one-time prompt was already used).
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            PermissionManager.openScreenRecordingSettings()
        }
        render(.waiting)
    }

    @objc private func startCapturing() { close() }

    // MARK: - Poll → relaunch

    private func startPolling() {
        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(timeInterval: 1.0, target: self,
                                         selector: #selector(pollPermission),
                                         userInfo: nil, repeats: true)
    }

    @objc private func pollPermission() {
        guard PermissionManager.hasScreenRecordingPermission else { return }
        pollTimer?.invalidate(); pollTimer = nil
        UserDefaults.standard.set(true, forKey: Self.relaunchFlagKey)
        PermissionManager.relaunchApp()
    }
}
