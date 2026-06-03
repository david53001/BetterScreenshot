import AppKit

public struct QuickAccessActions {
    public let onCopy: () -> Void
    public let onSave: () -> Void
    public let onAnnotate: () -> Void
    public let fileURLForDrag: () -> URL?
    public init(onCopy: @escaping () -> Void, onSave: @escaping () -> Void,
                onAnnotate: @escaping () -> Void, fileURLForDrag: @escaping () -> URL?) {
        self.onCopy = onCopy; self.onSave = onSave
        self.onAnnotate = onAnnotate; self.fileURLForDrag = fileURLForDrag
    }
}

public final class QuickAccessOverlayController {
    private var panel: NSPanel?
    private var dismissTimer: Timer?
    private var actions: QuickAccessActions?

    public init() {}

    /// Presents the overlay at the given screen origin (Cocoa bottom-left coords).
    public func present(image: NSImage, at origin: CGPoint,
                        autoDismissSeconds: Int, actions: QuickAccessActions) {
        dismiss()
        self.actions = actions

        let size = NSSize(width: 220, height: 168)
        let panel = NSPanel(contentRect: NSRect(origin: origin, size: size),
                            styleMask: [.nonactivatingPanel, .borderless],
                            backing: .buffered, defer: false)
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.hidesOnDeactivate = false

        let container = NSView(frame: NSRect(origin: .zero, size: size))
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        container.layer?.cornerRadius = 12

        let thumb = DraggableImageView(frame: NSRect(x: 10, y: 46, width: 200, height: 112))
        thumb.image = image
        thumb.imageScaling = .scaleProportionallyUpOrDown
        thumb.wantsLayer = true
        thumb.layer?.cornerRadius = 6
        thumb.layer?.masksToBounds = true
        thumb.fileURLProvider = actions.fileURLForDrag
        container.addSubview(thumb)

        let stack = NSStackView(frame: NSRect(x: 10, y: 8, width: 200, height: 30))
        stack.orientation = .horizontal
        stack.distribution = .fillEqually
        stack.spacing = 6
        stack.addArrangedSubview(button("Copy", #selector(copyAction)))
        stack.addArrangedSubview(button("Save", #selector(saveAction)))
        stack.addArrangedSubview(button("Edit", #selector(annotateAction)))
        stack.addArrangedSubview(button("✕", #selector(closeAction)))
        container.addSubview(stack)

        panel.contentView = container
        panel.orderFrontRegardless()
        self.panel = panel

        // Auto-dismiss unless hovered.
        let tracking = NSTrackingArea(rect: container.bounds,
            options: [.mouseEnteredAndExited, .activeAlways], owner: self, userInfo: nil)
        container.addTrackingArea(tracking)
        scheduleDismiss(after: autoDismissSeconds)
    }

    public func dismiss() {
        dismissTimer?.invalidate(); dismissTimer = nil
        panel?.orderOut(nil); panel = nil; actions = nil
    }

    private func scheduleDismiss(after seconds: Int) {
        dismissTimer?.invalidate()
        guard seconds > 0 else { return }
        dismissTimer = Timer.scheduledTimer(withTimeInterval: TimeInterval(seconds),
                                            repeats: false) { [weak self] _ in self?.dismiss() }
    }

    public func mouseEntered(with event: NSEvent) { dismissTimer?.invalidate() }
    public func mouseExited(with event: NSEvent) { scheduleDismiss(after: 3) }

    private func button(_ title: String, _ sel: Selector) -> NSButton {
        let b = NSButton(title: title, target: self, action: sel)
        b.bezelStyle = .rounded
        b.font = .systemFont(ofSize: 11)
        return b
    }

    @objc private func copyAction() { actions?.onCopy(); dismiss() }
    @objc private func saveAction() { actions?.onSave(); dismiss() }
    @objc private func annotateAction() { actions?.onAnnotate(); dismiss() }
    @objc private func closeAction() { dismiss() }
}

extension QuickAccessOverlayController {
    // NSTrackingArea calls require the owner to respond; route via the panel's content view owner.
    // (mouseEntered/mouseExited above are invoked because this controller is the tracking owner.)
}
