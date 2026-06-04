import AppKit

public final class SelectionOverlayController {
    private var windows: [NSWindow] = []
    private var completion: ((SelectionResult?) -> Void)?

    public init() {}

    /// Presents selection overlays on all screens; calls completion with the result (or nil if cancelled).
    public func present(completion: @escaping (SelectionResult?) -> Void) {
        self.completion = completion
        for screen in NSScreen.screens {
            let view = SelectionView(frame: screen.frame)
            view.onComplete = { [weak self] rect in self?.finish(rect: rect, screen: screen) }
            view.onCancel = { [weak self] in self?.finish(rect: nil, screen: screen) }
            let window = KeyableOverlayWindow(contentRect: screen.frame, styleMask: .borderless,
                                              backing: .buffered, defer: false, screen: screen)
            window.level = .screenSaver
            window.backgroundColor = .clear
            window.isOpaque = false
            window.ignoresMouseEvents = false
            window.contentView = view
            window.makeKeyAndOrderFront(nil)
            // Borderless windows can't become key by default; KeyableOverlayWindow
            // overrides that, so make the view first responder to receive Escape.
            window.makeFirstResponder(view)
            windows.append(window)
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    private func finish(rect: CGRect?, screen: NSScreen) {
        // Multiple overlays (one per display) can each call finish; only the
        // first wins. Clear completion first so it can never fire twice.
        guard let completion else { return }
        self.completion = nil
        windows.forEach { $0.orderOut(nil) }
        windows.removeAll()
        guard let rect, rect.width >= 1, rect.height >= 1 else { completion(nil); return }
        let displayID = (screen.deviceDescription[
            NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
        completion(SelectionResult(globalRect: rect, displayID: displayID))
    }
}

/// A borderless window that can still become key, so its view receives key
/// events (Escape to cancel). Plain borderless NSWindows return false here.
final class KeyableOverlayWindow: NSWindow {
    override var canBecomeKey: Bool { true }
}

final class SelectionView: NSView {
    var onComplete: ((CGRect) -> Void)?
    var onCancel: (() -> Void)?
    private var start: NSPoint?
    private var current: NSPoint?

    override var acceptsFirstResponder: Bool { true }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .crosshair) }

    override func mouseDown(with event: NSEvent) { start = convert(event.locationInWindow, from: nil) }
    override func mouseDragged(with event: NSEvent) {
        current = convert(event.locationInWindow, from: nil); needsDisplay = true
    }
    override func mouseUp(with event: NSEvent) {
        guard let s = start, let c = current else { onCancel?(); return }
        // Convert local view rect → global (window origin is screen origin here).
        let local = rectBetween(s, c)
        let global = window.map { NSRect(x: $0.frame.minX + local.minX,
                                         y: $0.frame.minY + local.minY,
                                         width: local.width, height: local.height) } ?? local
        onComplete?(global)
    }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { onCancel?() } // Escape
    }

    private func rectBetween(_ a: NSPoint, _ b: NSPoint) -> NSRect {
        NSRect(x: min(a.x, b.x), y: min(a.y, b.y),
               width: abs(a.x - b.x), height: abs(a.y - b.y))
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.35).setFill()
        bounds.fill()
        guard let s = start, let c = current else { return }
        let sel = rectBetween(s, c)
        // Punch out the selection.
        NSColor.clear.setFill()
        sel.fill(using: .copy)
        NSColor.white.setStroke()
        let path = NSBezierPath(rect: sel); path.lineWidth = 1; path.stroke()
        // Dimensions label.
        let label = "\(Int(sel.width)) × \(Int(sel.height))"
        let attrs: [NSAttributedString.Key: Any] = [
            .foregroundColor: NSColor.white,
            .font: NSFont.systemFont(ofSize: 12, weight: .medium)
        ]
        label.draw(at: NSPoint(x: sel.minX, y: sel.maxY + 4), withAttributes: attrs)
    }
}
