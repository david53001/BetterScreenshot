import AppKit

/// A centered countdown HUD shown before recording starts. Counts down once per
/// second; click to skip (start now); `cancel()` aborts. Uses the same dark-pill
/// recipe as OverlayKit's HUDController (replicated here — RecordingKit doesn't
/// depend on OverlayKit).
@MainActor
public final class CountdownOverlayController {
    private var panel: NSPanel?
    private var label: NSTextField?
    private var timer: Timer?
    private var remaining = 0
    private var continuation: CheckedContinuation<Void, Never>?

    public init() {}

    /// Shows the countdown centered on `screen`; returns when it finishes, is
    /// clicked (skip), or is cancelled. Always tears the overlay down first.
    public func run(seconds: Int, on screen: NSScreen) async {
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            self.continuation = cont
            self.present(seconds: seconds, on: screen)
        }
    }

    /// Aborts an in-flight countdown (no-op otherwise), resolving `run()`.
    public func cancel() { finish() }

    private func present(seconds: Int, on screen: NSScreen) {
        let side: CGFloat = 200
        let origin = NSPoint(x: screen.frame.midX - side / 2, y: screen.frame.midY - side / 2)
        let panel = NSPanel(contentRect: NSRect(origin: origin, size: NSSize(width: side, height: side)),
                            styleMask: [.nonactivatingPanel, .borderless],
                            backing: .buffered, defer: false)
        panel.level = .floating
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let container = ClickView(frame: NSRect(x: 0, y: 0, width: side, height: side))
        container.onClick = { [weak self] in self?.finish() }   // click to skip
        container.appearance = NSAppearance(named: .vibrantDark)
        container.material = .hudWindow
        container.state = .active
        container.wantsLayer = true
        container.layer?.cornerRadius = 24
        container.layer?.masksToBounds = true

        let label = NSTextField(labelWithString: "\(seconds)")
        label.font = .monospacedDigitSystemFont(ofSize: 120, weight: .semibold)
        label.textColor = .white
        label.alignment = .center
        label.frame = container.bounds
        label.autoresizingMask = [.width, .height]
        // Vertically center the baseline-ish: nudge using a cell that centers.
        label.cell?.lineBreakMode = .byClipping
        container.addSubview(label)

        panel.contentView = container
        panel.orderFrontRegardless()

        self.panel = panel
        self.label = label
        self.remaining = seconds
        self.timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            Task { @MainActor [weak self] in self?.tick() }
        }
    }

    private func tick() {
        remaining -= 1
        if remaining <= 0 { finish(); return }
        label?.stringValue = "\(remaining)"
    }

    private func finish() {
        timer?.invalidate(); timer = nil
        panel?.orderOut(nil); panel = nil
        label = nil
        let cont = continuation; continuation = nil
        cont?.resume()
    }
}

/// A vibrancy view that reports clicks (skip the countdown).
private final class ClickView: NSVisualEffectView {
    var onClick: (() -> Void)?
    override func mouseDown(with event: NSEvent) { onClick?() }
}
