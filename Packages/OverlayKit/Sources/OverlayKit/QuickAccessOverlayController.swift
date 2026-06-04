import AppKit

public struct QuickAccessActions {
    public let onCopy: () -> Void
    public let onSave: () -> Void
    public let onAnnotate: () -> Void
    public let onPin: () -> Void
    public let fileURLForDrag: () -> URL?
    public init(onCopy: @escaping () -> Void, onSave: @escaping () -> Void,
                onAnnotate: @escaping () -> Void, onPin: @escaping () -> Void,
                fileURLForDrag: @escaping () -> URL?) {
        self.onCopy = onCopy; self.onSave = onSave
        self.onAnnotate = onAnnotate; self.onPin = onPin
        self.fileURLForDrag = fileURLForDrag
    }
}

/// A floating post-capture thumbnail. It is PERSISTENT: it never auto-dismisses.
/// It goes away only when the user clicks ✕, clicks Save (download), drags the
/// thumbnail out to another app, or opens the editor.
///
/// NSObject subclass so it is a first-class Obj-C target for the buttons. The
/// previous version was a plain Swift class used as an NSTrackingArea owner,
/// which crashed (`doesNotRecognizeSelector: mouseEntered:`) the moment the
/// cursor entered the overlay — that whole auto-dismiss/tracking path is gone.
public final class QuickAccessOverlayController: NSObject {
    private var panel: NSPanel?
    private var actions: QuickAccessActions?

    /// Fired exactly once whenever a visible overlay goes away (✕, save,
    /// drag-out, annotate, pin, or eviction) so a stack manager can compact.
    public var onDismissed: (() -> Void)?

    public override init() { super.init() }

    /// Presents the overlay at the given screen origin (Cocoa bottom-left coords).
    public func present(image: NSImage, at origin: CGPoint, actions: QuickAccessActions) {
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
        // Dragging the thumbnail out makes it a temp file that self-deletes; once
        // it has been dropped somewhere, the overlay goes away.
        thumb.onDragEnded = { [weak self] droppedSomewhere in
            if droppedSomewhere { self?.dismiss() }
        }
        container.addSubview(thumb)

        let stack = NSStackView(frame: NSRect(x: 10, y: 8, width: 200, height: 30))
        stack.orientation = .horizontal
        stack.distribution = .fillEqually
        stack.spacing = 6
        stack.addArrangedSubview(iconButton("doc.on.doc", tip: "Copy", #selector(copyAction)))
        stack.addArrangedSubview(iconButton("pencil.tip.crop.circle", tip: "Edit", #selector(annotateAction)))
        stack.addArrangedSubview(iconButton("pin", tip: "Pin to screen", #selector(pinAction)))
        stack.addArrangedSubview(iconButton("square.and.arrow.down", tip: "Save to screenshots", #selector(saveAction)))
        stack.addArrangedSubview(iconButton("xmark", tip: "Close", #selector(closeAction)))
        container.addSubview(stack)

        panel.contentView = container
        panel.orderFrontRegardless()
        self.panel = panel
        // No auto-dismiss timer and no tracking area: the overlay is persistent.
    }

    public func dismiss() {
        guard panel != nil else { return }
        panel?.orderOut(nil); panel = nil; actions = nil
        onDismissed?()
    }

    /// Slides the overlay to a new stack slot.
    public func move(to origin: CGPoint) {
        panel?.setFrameOrigin(origin)
    }

    private func iconButton(_ symbol: String, tip: String, _ sel: Selector) -> NSButton {
        let b = NSButton(title: "", target: self, action: sel)
        b.bezelStyle = .rounded
        b.image = NSImage(systemSymbolName: symbol, accessibilityDescription: tip)
            ?? NSImage(size: NSSize(width: 1, height: 1))
        b.imagePosition = .imageOnly
        b.toolTip = tip
        return b
    }

    // Copy keeps the overlay up (so the user can still save/drag/close it).
    @objc private func copyAction() { actions?.onCopy() }
    // Save writes to the screenshot folder, then dismisses.
    @objc private func saveAction() { actions?.onSave(); dismiss() }
    // Opening the editor takes over from the overlay.
    @objc private func annotateAction() {
        let a = actions
        dismiss()
        a?.onAnnotate()
    }
    // Pinning replaces the overlay with a floating pin.
    @objc private func pinAction() {
        let a = actions
        dismiss()
        a?.onPin()
    }
    @objc private func closeAction() { dismiss() }
}
